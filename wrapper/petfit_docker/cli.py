"""Command line wrapper for running PETFit in Docker."""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Sequence

from ._version import __version__

DEFAULT_IMAGE = "mathesong/petfit:latest"
DEFAULT_PLATFORM = "linux/amd64"
DEFAULT_PORT = 3838
APPS = ("regiondef", "modelling_plasma", "modelling_ref")
MODES = ("automatic", "interactive")
STEPS = ("datadef", "weights", "delay", "reference_tac", "model1", "model2", "model3")
MISSING_IMAGE = "Image '{}' is missing\nWould you like to download? [Y/n] "


class PETFitHelpFormatter(argparse.ArgumentDefaultsHelpFormatter, argparse.RawDescriptionHelpFormatter):
    """Preserve paragraphs while still showing defaults."""


class PathAction(argparse.Action):
    """Expand user paths while preserving argparse's standard display."""

    def __call__(self, parser, namespace, values, option_string=None):
        if values is None:
            setattr(namespace, self.dest, None)
            return
        if isinstance(values, list):
            setattr(namespace, self.dest, [str(Path(value).expanduser()) for value in values])
        else:
            setattr(namespace, self.dest, str(Path(values).expanduser()))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="petfit-docker",
        formatter_class=PETFitHelpFormatter,
        description=(
            "The PETFit on Docker wrapper\n\n"
            "This is a lightweight Python wrapper to run PETFit. Docker must be "
            "installed and running. This can be checked running::\n\n"
            "    docker info\n\n"
            "The wrapper accepts a BIDS-App-like command line and translates host "
            "paths into Docker bind mounts before executing the PETFit image."
        ),
    )

    parser.add_argument("bids_dir", nargs="?", action=PathAction)
    parser.add_argument("output_dir", nargs="?", action=PathAction)
    parser.add_argument("analysis_level", nargs="?", choices=("participant",), default="participant")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument("-i", "--image", default=DEFAULT_IMAGE, help="image name")

    wrapper = parser.add_argument_group(
        "Wrapper options",
        "Standard options that require mapping files into the container; see petfit usage for complete descriptions",
    )
    wrapper.add_argument("--app", choices=APPS, default="regiondef", help="PETFit app to run")
    wrapper.add_argument("--mode", choices=MODES, default="interactive", help="execution mode")
    wrapper.add_argument(
        "--interactive",
        dest="mode",
        action="store_const",
        const="interactive",
        default=argparse.SUPPRESS,
        help="run the Shiny app",
    )
    wrapper.add_argument(
        "--automatic",
        dest="mode",
        action="store_const",
        const="automatic",
        default=argparse.SUPPRESS,
        help="run the automatic pipeline",
    )
    wrapper.add_argument("--step", choices=STEPS, help="single automatic modelling step to run")
    wrapper.add_argument("--blood-dir", action=PathAction, help="blood data directory for plasma input models")
    wrapper.add_argument("-w", "--work-dir", action=PathAction, help="working directory to mount in the container")
    wrapper.add_argument("--petfit-output-foldername", default="petfit", help="petfit output folder within derivatives")
    wrapper.add_argument("--analysis-foldername", default="Primary_Analysis", help="analysis folder name")
    wrapper.add_argument("--cores", type=int, default=1, help="number of cores for parallel processing")
    wrapper.add_argument(
        "--ancillary-analysis-folder",
        help="sibling analysis folder to inherit delay or k2prime estimates from",
    )
    wrapper.add_argument("--port", type=int, default=DEFAULT_PORT, help="host and container port for interactive Shiny apps")

    developer = parser.add_argument_group("Developer options", "Tools for testing and debugging PETFit")
    developer.add_argument("--shell", action="store_true", help="open shell in image instead of running PETFit")
    developer.add_argument(
        "-f",
        "--patch",
        action=PathAction,
        help="local petfit checkout to install over the image's petfit at container "
        "start (for testing local changes without rebuilding the image)",
    )
    developer.add_argument(
        "-e",
        "--env",
        nargs=2,
        action="append",
        metavar=("ENV_VAR", "value"),
        help="set custom environment variables within container",
    )
    developer.add_argument(
        "-u",
        "--user",
        help="run container as a given user/uid. A group/gid can also be assigned, i.e. --user <UID>:<GID>",
    )
    developer.add_argument("--network", help='run container with a different network driver, e.g. "none"')
    developer.add_argument(
        "--platform",
        default=DEFAULT_PLATFORM,
        help="run Docker with a specific platform; PETFit images are currently published for linux/amd64",
    )
    developer.add_argument("--no-tty", action="store_true", help="run docker without TTY flag -it")
    developer.add_argument("--dry-run", action="store_true", help="print the Docker command without executing it")
    developer.add_argument(
        "--skip-image-check",
        action="store_true",
        help="do not check whether the Docker image exists before running",
    )

    return parser


def _absolute_path(path: Optional[str], *, create: bool = False) -> Optional[str]:
    if path is None:
        return None

    resolved = Path(path).expanduser().absolute()
    if create:
        resolved.mkdir(parents=True, exist_ok=True)
    return str(resolved)


def _derivatives_mount_from_output(output_dir: str, petfit_output_foldername: str) -> str:
    """Map BIDS-App-like output_dir to PETFit's derivatives mount point.

    PETFit's container entry point expects the derivatives root and then appends
    ``petfit_output_foldername`` internally. If the wrapper user passes the final
    PETFit output directory, such as ``derivatives/petfit``, mount its parent so
    the container does not look for ``petfit/petfit``.
    """

    output_path = Path(output_dir)
    if output_path.name == petfit_output_foldername:
        return str(output_path.parent)
    return output_dir


def _mount_argument(host_path: str, container_path: str, mode: str) -> str:
    return f"{host_path}:{container_path}:{mode}"


def build_docker_command(opts: argparse.Namespace) -> List[str]:
    """Build the Docker command corresponding to parsed options."""

    if opts.mode == "interactive" and (opts.port < 1 or opts.port > 65535):
        raise SystemExit("--port must be between 1 and 65535")
    if opts.cores < 1:
        raise SystemExit("--cores must be at least 1")
    if opts.app == "regiondef" and opts.step:
        raise SystemExit("--step is only valid for modelling_plasma and modelling_ref")

    bids_dir = _absolute_path(opts.bids_dir) if opts.bids_dir else None
    output_dir = _absolute_path(opts.output_dir, create=not opts.shell) if opts.output_dir else None
    derivatives_dir = (
        _derivatives_mount_from_output(output_dir, opts.petfit_output_foldername)
        if output_dir
        else None
    )
    blood_dir = _absolute_path(opts.blood_dir) if opts.blood_dir else None
    work_dir = _absolute_path(opts.work_dir, create=True) if opts.work_dir else None

    if not opts.shell:
        missing = []
        if not bids_dir:
            missing.append("bids_dir")
        if not output_dir:
            missing.append("output_dir")
        if missing:
            raise SystemExit("the following arguments are required unless --shell is used: " + ", ".join(missing))

    command = ["docker", "run", "--rm"]
    if opts.platform:
        command.extend(["--platform", opts.platform])
    if not opts.no_tty:
        command.append("-it")

    if opts.user:
        command.extend(["--user", opts.user])
    if opts.network:
        command.extend(["--network", opts.network])

    env = list(opts.env or [])
    if opts.mode == "interactive":
        env.append(("PETFIT_SHINY_PORT", str(opts.port)))
        env.append(("SHINY_SERVER_VERSION", ""))
        command.extend(["-p", f"{opts.port}:{opts.port}"])

    for key, value in env:
        command.extend(["-e", f"{key}={value}"])

    if bids_dir:
        command.extend(["-v", _mount_argument(bids_dir, "/data/bids_dir", "ro")])
    if derivatives_dir:
        command.extend(["-v", _mount_argument(derivatives_dir, "/data/derivatives_dir", "rw")])
    if blood_dir:
        command.extend(["-v", _mount_argument(blood_dir, "/data/blood_dir", "ro")])
    if work_dir:
        command.extend(["-v", _mount_argument(work_dir, "/data/work_dir", "rw")])

    patch_dir = _absolute_path(opts.patch) if opts.patch else None
    if patch_dir:
        command.extend(["-v", _mount_argument(patch_dir, "/patch/petfit", "ro")])

    if opts.shell:
        command.extend(["--entrypoint", "/bin/bash", opts.image])
        return command

    command.append(opts.image)
    command.extend(
        [
            "--func",
            opts.app,
            "--mode",
            opts.mode,
            "--petfit_output_foldername",
            opts.petfit_output_foldername,
            "--analysis_foldername",
            opts.analysis_foldername,
            "--cores",
            str(opts.cores),
        ]
    )

    if opts.step:
        command.extend(["--step", opts.step])
    if opts.ancillary_analysis_folder:
        command.extend(["--ancillary_analysis_folder", opts.ancillary_analysis_folder])

    return command


def check_docker() -> None:
    """Fail early if Docker is unavailable, preserving Docker's own message."""

    try:
        subprocess.run(["docker", "info"], capture_output=True, text=True, check=True)
    except OSError as error:
        raise SystemExit(f"Could not run Docker: {error}") from error
    except subprocess.CalledProcessError as error:
        docker_output = (error.stderr or error.stdout or "").strip()
        if docker_output:
            print(docker_output, file=sys.stderr)
        print("Could not detect memory capacity of Docker container.", file=sys.stderr)
        raise SystemExit("Do you have permission to run docker?") from error

    return None


def image_exists(image: str) -> bool:
    """Return whether a Docker image is available locally."""

    try:
        result = subprocess.run(["docker", "images", "-q", image], stdout=subprocess.PIPE)
    except OSError:
        return False
    return bool(result.stdout)


def check_memory(image: str, platform: Optional[str] = DEFAULT_PLATFORM) -> int:
    """Return available container memory in MB, or -1 if Docker cannot report it."""

    command = ["docker", "run", "--rm"]
    if platform:
        command.extend(["--platform", platform])
    command.extend(["--entrypoint=free", image, "-m"])

    try:
        result = subprocess.run(command, stdout=subprocess.PIPE)
    except OSError:
        return -1

    if result.returncode:
        return -1

    for line in result.stdout.splitlines():
        if line.startswith(b"Mem:"):
            return int(line.decode().split()[1])
    return -1


def maybe_pull_image(image: str) -> None:
    """Offer to download a missing image before Docker pulls via ``docker run``."""

    if image_exists(image):
        return

    answer = input(MISSING_IMAGE.format(image))
    if answer.strip().lower() not in ("", "y", "yes"):
        raise SystemExit(f"Image '{image}' is required")

    print("Downloading. This may take a while...", flush=True)


def ensure_image_ready(image: str, platform: Optional[str] = DEFAULT_PLATFORM) -> None:
    """Confirm image availability and that Docker can run a tiny memory probe."""

    maybe_pull_image(image)
    if check_memory(image, platform=platform) == -1:
        print("Could not detect memory capacity of Docker container.", file=sys.stderr)
        raise SystemExit("Do you have permission to run docker?")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = _parser()
    opts = parser.parse_args(argv)

    if not opts.dry_run:
        check_docker()
        if not opts.skip_image_check:
            ensure_image_ready(opts.image, platform=opts.platform)

    command = build_docker_command(opts)
    print("RUNNING: " + shlex.join(command))

    if opts.dry_run:
        return 0
    return subprocess.call(command)
