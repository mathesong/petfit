"""Tell users when a newer petfit-docker or PETFit image is available.

Neither pip nor Docker does this: pip never checks installed packages, and
``docker run`` keeps using whatever copy of ``mathesong/petfit:latest`` is on the
computer. So without a check, users keep running old versions indefinitely.

The check only prints a message. It never updates anything, because a study part
way through its analysis needs to stay on the version it started with.

What PyPI and Docker Hub report is saved, and asked again at most once a day, so
most runs make no network requests at all. The comparison with what is installed
is made on every run, so the message goes away as soon as the user updates. Any
failure, such as having no network on an HPC compute node, is silent, and the
wrapper never waits on the network for more than a few seconds.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from pathlib import Path
from typing import Callable, Dict, Optional, Tuple

from ._version import __version__

DISABLE_ENV = "PETFIT_NO_UPDATE_CHECK"
CHECK_INTERVAL = 24 * 60 * 60
TIMEOUT = 2
# urlopen's timeout does not cover looking up the host name, so the wait for an
# answer is bounded separately
DEADLINE = 3
PYPI_URL = "https://pypi.org/pypi/petfit-docker/json"
DOCKER_HUB_REPOSITORY = "mathesong/petfit"
DOCKER_HUB_URL = (
    "https://hub.docker.com/v2/repositories/" + DOCKER_HUB_REPOSITORY
    + "/tags?page_size=25&ordering=last_updated"
)


def update_check_disabled() -> bool:
    """Return whether the user has turned the check off with the environment variable."""

    return os.environ.get(DISABLE_ENV, "").strip().lower() not in ("", "0", "false", "no")


def cache_path() -> Path:
    """Where the latest versions reported by PyPI and Docker Hub are saved."""

    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "petfit-docker" / "update_check.json"


def _parse_version(version: str) -> Optional[Tuple[int, ...]]:
    """Read a release version such as ``0.2.4`` or ``v0.2.4``; anything else is ``None``."""

    match = re.fullmatch(r"v?(\d+(?:\.\d+)*)", version.strip())
    if not match:
        return None
    parts = [int(part) for part in match.group(1).split(".")]
    # 0.3 and 0.3.0 are the same release
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def is_newer(candidate: Optional[str], current: Optional[str]) -> bool:
    """Return whether ``candidate`` is a later release than ``current``.

    A version which is not a plain release, such as a development version, is
    never compared, so developers are not told to downgrade.
    """

    if not candidate or not current:
        return False
    candidate_parts = _parse_version(candidate)
    current_parts = _parse_version(current)
    if candidate_parts is None or current_parts is None:
        return False
    return candidate_parts > current_parts


def _get_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": f"petfit-docker/{__version__}"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


def fetch_latest_wrapper() -> str:
    """Return the newest petfit-docker version on PyPI."""

    return _get_json(PYPI_URL)["info"]["version"]


def fetch_latest_image() -> Dict[str, str]:
    """Return the digest of each recent image tag on Docker Hub, including ``latest``.

    The other tags (``v0.2.4`` and so on) are what let the message name versions,
    since the image itself does not record one.
    """

    results = _get_json(DOCKER_HUB_URL)["results"]
    tags = {tag["name"]: tag["digest"] for tag in results if tag.get("digest")}
    if "latest" not in tags:
        raise ValueError("Docker Hub did not report a 'latest' tag")
    return tags


def local_image_digests(image: str) -> list:
    """Return the registry digests of the local image, or an empty list.

    An image built locally and never pushed or pulled has none, so it cannot be
    compared, and is not reported on.
    """

    try:
        result = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{json .RepoDigests}}", image],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode:
        return []
    try:
        repo_digests = json.loads(result.stdout) or []
    except ValueError:
        return []
    return [entry.split("@", 1)[1] for entry in repo_digests if "@" in entry]


def _read_cache(path: Path) -> dict:
    try:
        cached = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return cached if isinstance(cached, dict) else {}


def _write_cache(path: Path, cached: dict) -> None:
    """Replace the cache in one step, so a run started at the same time never reads half a file."""

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        handle, temporary = tempfile.mkstemp(dir=str(path.parent), prefix=".update_check.")
        try:
            with os.fdopen(handle, "w") as file:
                json.dump(cached, file)
            os.replace(temporary, str(path))
        except BaseException:
            os.unlink(temporary)
            raise
    except OSError:
        pass


def _fetch_all(fetchers: Dict[str, Callable[[], object]]) -> Dict[str, object]:
    """Run the requests together, and return the answers which arrive in time.

    They run in daemon threads, which are abandoned rather than waited for: a
    request stuck looking up a host name then cannot hold up PETFit, or its exit.
    """

    answers: Dict[str, object] = {}

    def run(key: str, fetch: Callable[[], object]) -> None:
        try:
            answers[key] = fetch()
        except Exception:
            pass

    threads = [
        threading.Thread(target=run, args=(key, fetch), daemon=True)
        for key, fetch in fetchers.items()
    ]
    for thread in threads:
        thread.start()
    deadline = time.monotonic() + DEADLINE
    for thread in threads:
        thread.join(max(0.0, deadline - time.monotonic()))
    return {key: answers[key] for key in fetchers if key in answers}


def latest_versions(path: Path, check_image: bool = True, now: Optional[float] = None) -> dict:
    """Return the latest versions, asking PyPI and Docker Hub if a day has passed.

    Each source is saved as ``{"checked": time, "value": answer}``. The time of an
    attempt is saved even when it fails, so an offline computer does not wait on
    the network every time it runs; a failed request keeps the last answer which
    worked. Docker Hub is only asked when the image is to be checked.
    """

    now = time.time() if now is None else now
    cached = _read_cache(path)

    def due(key: str) -> bool:
        entry = cached.get(key)
        checked = entry.get("checked") if isinstance(entry, dict) else None
        return not (isinstance(checked, (int, float)) and 0 <= now - checked < CHECK_INTERVAL)

    fetchers: Dict[str, Callable[[], object]] = {}
    if due("wrapper"):
        fetchers["wrapper"] = fetch_latest_wrapper
    if check_image and due("image_tags"):
        fetchers["image_tags"] = fetch_latest_image

    if fetchers:
        answers = _fetch_all(fetchers)
        for key in fetchers:
            previous = cached.get(key) if isinstance(cached.get(key), dict) else {}
            cached[key] = {"checked": now, "value": answers.get(key, previous.get("value"))}
        _write_cache(path, cached)

    return {
        key: entry.get("value")
        for key, entry in cached.items()
        if isinstance(entry, dict)
    }


def update_messages(latest: dict, local_digests: Optional[list]) -> list:
    """Compare what is installed with the latest versions, and say what to update.

    ``local_digests`` is ``None`` when the image is not to be checked.
    """

    messages = []

    latest_wrapper = latest.get("wrapper")
    if isinstance(latest_wrapper, str) and is_newer(latest_wrapper, __version__):
        messages.append(
            f"A newer petfit-docker is available ({latest_wrapper}; you have {__version__}). "
            "Update it with: pip install -U petfit-docker"
        )

    tags = latest.get("image_tags")
    if local_digests and isinstance(tags, dict) and tags.get("latest"):
        latest_digest = tags["latest"]
        versions = {name: digest for name, digest in tags.items() if name != "latest"}
        newest = next((name for name, digest in versions.items() if digest == latest_digest), None)
        installed = next((name for name, digest in versions.items() if digest in local_digests), None)
        # Only an image known to be a release other than the latest is reported.
        # An unknown one may be newer than what was saved, such as a release
        # pulled since the last check, or a build of the user's own.
        older = (
            latest_digest not in local_digests
            and installed is not None
            and (newest is None or is_newer(newest, installed))
        )
        if older:
            detail = f" ({newest}; you have {installed})" if newest else f" (you have {installed})"
            messages.append(
                f"A newer PETFit image is available{detail}. "
                f"Update it with: docker pull {DOCKER_HUB_REPOSITORY}:latest"
            )

    return messages


def check_for_updates(check_image: bool, image: str) -> None:
    """Print a note to stderr for each update available. Never raises."""

    try:
        if update_check_disabled():
            return
        latest = latest_versions(cache_path(), check_image=check_image)
        local_digests = local_image_digests(image) if check_image else None
        messages = update_messages(latest, local_digests)
        if messages:
            for message in messages:
                print(message, file=sys.stderr)
            print(
                f"To turn off this check, use --no-update-check or set {DISABLE_ENV}=1.",
                file=sys.stderr,
            )
    except Exception:
        pass
