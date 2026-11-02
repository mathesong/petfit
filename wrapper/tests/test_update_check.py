import json
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from petfit_docker import update_check
from petfit_docker.update_check import (
    CHECK_INTERVAL,
    check_for_updates,
    is_newer,
    latest_versions,
    local_image_digests,
    update_messages,
)

NEW = "sha256:" + "a" * 64
OLD = "sha256:" + "b" * 64
TAGS = {"latest": NEW, "v9.9.9": NEW, "v0.0.1": OLD}


class VersionComparisonTests(unittest.TestCase):
    def test_later_release_is_newer(self):
        self.assertTrue(is_newer("0.2.10", "0.2.9"))
        self.assertTrue(is_newer("v0.3.0", "0.2.9"))

    def test_same_or_earlier_release_is_not_newer(self):
        self.assertFalse(is_newer("0.2.4", "0.2.4"))
        self.assertFalse(is_newer("0.2.3", "0.2.4"))

    def test_trailing_zeros_do_not_make_a_version_newer(self):
        self.assertFalse(is_newer("0.2.0", "0.2"))
        self.assertFalse(is_newer("0.2", "0.2.0"))
        self.assertTrue(is_newer("0.2.1", "0.2"))

    def test_unreadable_versions_are_never_newer(self):
        self.assertFalse(is_newer("0.3.0", "0.2.4.dev1+local"))
        self.assertFalse(is_newer("0.3.0rc1", "0.2.4"))
        self.assertFalse(is_newer(None, "0.2.4"))


class MessageTests(unittest.TestCase):
    def test_newer_wrapper_is_reported(self):
        with patch.object(update_check, "__version__", "0.2.4"):
            messages = update_messages({"wrapper": "0.2.5"}, None)

        self.assertEqual(len(messages), 1)
        self.assertIn("0.2.5; you have 0.2.4", messages[0])
        self.assertIn("pip install -U petfit-docker", messages[0])

    def test_current_wrapper_is_not_reported(self):
        with patch.object(update_check, "__version__", "0.2.5"):
            self.assertEqual(update_messages({"wrapper": "0.2.5"}, None), [])

    def test_older_image_is_reported_with_both_versions(self):
        messages = update_messages({"image_tags": TAGS}, [OLD])

        self.assertEqual(len(messages), 1)
        self.assertIn("(v9.9.9; you have v0.0.1)", messages[0])
        self.assertIn("docker pull mathesong/petfit:latest", messages[0])

    def test_current_image_is_not_reported(self):
        self.assertEqual(update_messages({"image_tags": TAGS}, [NEW]), [])

    def test_unknown_local_image_is_not_reported(self):
        # Such as a release pulled since the last check, or the user's own build
        self.assertEqual(update_messages({"image_tags": TAGS}, ["sha256:" + "c" * 64]), [])

    def test_image_newer_than_the_saved_latest_is_not_reported(self):
        # v9.9.10 was tagged before latest was moved to it
        tags = dict(TAGS, **{"v9.9.10": "sha256:" + "c" * 64})
        self.assertEqual(update_messages({"image_tags": tags}, ["sha256:" + "c" * 64]), [])

    def test_older_image_is_reported_when_latest_has_no_version_tag(self):
        messages = update_messages({"image_tags": {"latest": NEW, "v0.0.1": OLD}}, [OLD])
        self.assertIn("(you have v0.0.1)", messages[0])

    def test_image_is_not_compared_without_local_digests(self):
        # None: not to be checked; []: built locally, so nothing to compare
        self.assertEqual(update_messages({"image_tags": TAGS}, None), [])
        self.assertEqual(update_messages({"image_tags": TAGS}, []), [])


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "petfit-docker" / "update_check.json"

    def tearDown(self):
        self.tmp.cleanup()

    def save(self, cached):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(cached))

    def test_first_check_asks_and_saves(self):
        with patch.object(update_check, "fetch_latest_wrapper", return_value="0.3.0"):
            with patch.object(update_check, "fetch_latest_image", return_value=TAGS):
                latest = latest_versions(self.path, now=1000.0)

        self.assertEqual(latest, {"wrapper": "0.3.0", "image_tags": TAGS})
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved["wrapper"], {"checked": 1000.0, "value": "0.3.0"})
        # Written in one step, so no temporary file is left beside it
        self.assertEqual([p.name for p in self.path.parent.iterdir()], ["update_check.json"])

    def test_recent_check_does_not_ask_again(self):
        self.save({
            "wrapper": {"checked": 1000.0, "value": "0.3.0"},
            "image_tags": {"checked": 1000.0, "value": TAGS},
        })

        with patch.object(update_check, "fetch_latest_wrapper") as fetch_wrapper:
            with patch.object(update_check, "fetch_latest_image") as fetch_image:
                latest = latest_versions(self.path, now=1000.0 + CHECK_INTERVAL - 1)

        fetch_wrapper.assert_not_called()
        fetch_image.assert_not_called()
        self.assertEqual(latest["wrapper"], "0.3.0")

    def test_failed_check_keeps_old_values_and_waits_a_day(self):
        self.save({
            "wrapper": {"checked": 0.0, "value": "0.3.0"},
            "image_tags": {"checked": 0.0, "value": TAGS},
        })

        with patch.object(update_check, "fetch_latest_wrapper", side_effect=OSError("offline")):
            with patch.object(update_check, "fetch_latest_image", side_effect=OSError("offline")):
                latest = latest_versions(self.path, now=CHECK_INTERVAL + 1.0)

        self.assertEqual(latest, {"wrapper": "0.3.0", "image_tags": TAGS})

        with patch.object(update_check, "fetch_latest_wrapper") as fetch:
            latest_versions(self.path, now=CHECK_INTERVAL + 2.0)
        fetch.assert_not_called()

    def test_docker_hub_is_not_asked_when_the_image_is_not_checked(self):
        with patch.object(update_check, "fetch_latest_wrapper", return_value="0.3.0"):
            with patch.object(update_check, "fetch_latest_image") as fetch_image:
                latest_versions(self.path, check_image=False, now=1000.0)

        fetch_image.assert_not_called()

        # A later run with the default image still asks, the same day
        with patch.object(update_check, "fetch_latest_wrapper") as fetch_wrapper:
            with patch.object(update_check, "fetch_latest_image", return_value=TAGS):
                latest = latest_versions(self.path, now=1001.0)

        fetch_wrapper.assert_not_called()
        self.assertEqual(latest["image_tags"], TAGS)

    def test_corrupt_cache_is_replaced(self):
        self.save("not a dictionary")

        with patch.object(update_check, "fetch_latest_wrapper", return_value="0.3.0"):
            with patch.object(update_check, "fetch_latest_image", return_value=TAGS):
                latest = latest_versions(self.path, now=1000.0)

        self.assertEqual(latest["wrapper"], "0.3.0")

    def test_unwritable_cache_is_ignored(self):
        with patch.object(update_check, "fetch_latest_wrapper", return_value="0.3.0"):
            with patch.object(update_check, "fetch_latest_image", return_value=TAGS):
                with patch("tempfile.mkstemp", side_effect=PermissionError("read-only")):
                    latest = latest_versions(self.path, now=1000.0)

        self.assertEqual(latest["wrapper"], "0.3.0")

    def test_a_request_which_hangs_is_abandoned(self):
        release = threading.Event()

        def hang():
            release.wait(30)
            return "0.3.0"

        try:
            with patch.object(update_check, "DEADLINE", 0.2):
                with patch.object(update_check, "fetch_latest_wrapper", side_effect=hang):
                    with patch.object(update_check, "fetch_latest_image", return_value=TAGS):
                        started = time.monotonic()
                        latest = latest_versions(self.path, now=1000.0)
                        waited = time.monotonic() - started
        finally:
            release.set()

        self.assertLess(waited, 2)
        self.assertIsNone(latest["wrapper"])
        self.assertEqual(latest["image_tags"], TAGS)


class LocalDigestTests(unittest.TestCase):
    def test_digests_are_read_from_repo_digests(self):
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(["mathesong/petfit@" + NEW]))
        with patch("subprocess.run", return_value=result):
            self.assertEqual(local_image_digests("mathesong/petfit:latest"), [NEW])

    def test_missing_image_or_docker_gives_no_digests(self):
        with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 1, stdout="")):
            self.assertEqual(local_image_digests("mathesong/petfit:latest"), [])
        with patch("subprocess.run", side_effect=OSError("no docker")):
            self.assertEqual(local_image_digests("mathesong/petfit:latest"), [])


class CheckForUpdatesTests(unittest.TestCase):
    def test_messages_go_to_stderr_with_how_to_turn_off(self):
        with patch.object(update_check, "update_check_disabled", return_value=False):
            with patch.object(update_check, "latest_versions", return_value={"image_tags": TAGS}):
                with patch.object(update_check, "local_image_digests", return_value=[OLD]):
                    with patch("sys.stderr", new=StringIO()) as stderr:
                        check_for_updates(check_image=True, image="mathesong/petfit:latest")

        self.assertIn("A newer PETFit image is available", stderr.getvalue())
        self.assertIn("--no-update-check", stderr.getvalue())

    def test_environment_variable_turns_the_check_off(self):
        for value, disabled in (("1", True), ("true", True), ("0", False), ("", False)):
            with self.subTest(value=value):
                with patch.dict("os.environ", {"PETFIT_NO_UPDATE_CHECK": value}):
                    self.assertEqual(update_check.update_check_disabled(), disabled)

    def test_disabled_check_makes_no_requests(self):
        with patch.dict("os.environ", {"PETFIT_NO_UPDATE_CHECK": "1"}):
            with patch.object(update_check, "latest_versions") as latest:
                check_for_updates(check_image=True, image="mathesong/petfit:latest")

        latest.assert_not_called()

    def test_image_is_not_inspected_when_not_checked(self):
        with patch.object(update_check, "update_check_disabled", return_value=False):
            with patch.object(update_check, "latest_versions", return_value={"image_tags": TAGS}):
                with patch.object(update_check, "local_image_digests") as inspect:
                    with patch("sys.stderr", new=StringIO()) as stderr:
                        check_for_updates(check_image=False, image="mathesong/petfit:v0.0.1")

        inspect.assert_not_called()
        self.assertEqual(stderr.getvalue(), "")

    def test_errors_never_stop_the_wrapper(self):
        with patch.object(update_check, "update_check_disabled", return_value=False):
            with patch.object(update_check, "latest_versions", side_effect=RuntimeError("boom")):
                check_for_updates(check_image=True, image="mathesong/petfit:latest")


if __name__ == "__main__":
    unittest.main()
