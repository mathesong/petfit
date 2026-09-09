import tempfile
import unittest
from pathlib import Path
import sys
from io import StringIO
from unittest.mock import patch
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from petfit_docker.cli import (
    _parser,
    build_docker_command,
    check_docker,
    check_memory,
    ensure_image_ready,
    main,
    maybe_pull_image,
)


def abs_path(path):
    return str(Path(path).expanduser().absolute())


class DockerCommandTests(unittest.TestCase):
    def test_no_arguments_parse_without_path_traceback(self):
        opts = _parser().parse_args([])

        self.assertIsNone(opts.bids_dir)
        self.assertIsNone(opts.output_dir)

    def test_builds_bids_app_like_modelling_command(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids = root / "bids"
            derivatives = root / "derivatives"
            blood = root / "blood"
            bids.mkdir()
            blood.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "modelling_plasma",
                    "--blood-dir",
                    str(blood),
                    "--step",
                    "weights",
                    "--automatic",
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn("docker", command)
            self.assertIn("--func", command)
            self.assertIn("modelling_plasma", command)
            self.assertIn("--platform", command)
            self.assertIn("linux/amd64", command)
            self.assertIn("--step", command)
            self.assertIn("weights", command)
            self.assertIn(f"{abs_path(bids)}:/data/bids_dir:ro", command)
            self.assertIn(f"{abs_path(derivatives)}:/data/derivatives_dir:rw", command)
            self.assertIn(f"{abs_path(blood)}:/data/blood_dir:ro", command)
            self.assertTrue(derivatives.exists())

    def test_interactive_mode_is_default(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids = root / "bids"
            derivatives = root / "derivatives"
            bids.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "regiondef",
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            mode_index = command.index("--mode")
            self.assertEqual(command[mode_index + 1], "interactive")
            self.assertIn("PETFIT_SHINY_PORT=3838", command)
            self.assertIn("SHINY_SERVER_VERSION=", command)

    def test_output_dir_can_be_final_petfit_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids = root / "bids"
            derivatives = root / "derivatives"
            petfit_output = derivatives / "petfit"
            bids.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(petfit_output),
                    "participant",
                    "--app",
                    "regiondef",
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn(f"{abs_path(derivatives)}:/data/derivatives_dir:rw", command)
            self.assertNotIn(f"{abs_path(petfit_output)}:/data/derivatives_dir:rw", command)
            self.assertTrue(petfit_output.exists())

    def test_interactive_mode_maps_port_and_env(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids = root / "bids"
            derivatives = root / "derivatives"
            bids.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--mode",
                    "interactive",
                    "--port",
                    "3840",
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn("-p", command)
            self.assertIn("3840:3840", command)
            self.assertIn("-e", command)
            self.assertIn("PETFIT_SHINY_PORT=3840", command)

    def test_patch_mounts_local_petfit(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids = root / "bids"
            derivatives = root / "derivatives"
            patch = root / "petfit"
            bids.mkdir()
            patch.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "regiondef",
                    "--patch",
                    str(patch),
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn(f"{abs_path(patch)}:/patch/petfit:ro", command)

    def test_patch_works_with_shell(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            patch = Path(tmpdir) / "petfit"
            patch.mkdir()

            opts = _parser().parse_args(
                [
                    "--shell",
                    "--patch",
                    str(patch),
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn(f"{abs_path(patch)}:/patch/petfit:ro", command)

    def test_regiondef_rejects_step(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids = root / "bids"
            derivatives = root / "derivatives"
            bids.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "regiondef",
                    "--step",
                    "weights",
                ]
            )

            with self.assertRaises(SystemExit):
                build_docker_command(opts)

    def test_check_docker_surfaces_daemon_error(self):
        error = subprocess.CalledProcessError(
            1,
            ["docker", "info"],
            stderr="Cannot connect to the Docker daemon at unix:///tmp/docker.sock. Is the docker daemon running?\n",
        )

        with patch("petfit_docker.cli.subprocess.run", side_effect=error):
            with patch("sys.stderr", new_callable=StringIO) as stderr:
                with self.assertRaises(SystemExit) as caught:
                    check_docker()

        self.assertIn("Cannot connect to the Docker daemon", stderr.getvalue())
        self.assertIn("Could not detect memory capacity", stderr.getvalue())
        self.assertEqual(str(caught.exception), "Do you have permission to run docker?")

    def test_main_checks_docker_and_image_before_required_paths(self):
        with patch("petfit_docker.cli.check_docker") as docker_check:
            with patch("petfit_docker.cli.ensure_image_ready") as ensure_image:
                with self.assertRaises(SystemExit) as caught:
                    main([])

        docker_check.assert_called_once()
        ensure_image.assert_called_once_with("mathesong/petfit:latest", platform="linux/amd64")
        self.assertIn("bids_dir", str(caught.exception))

    def test_main_stops_on_docker_failure_before_image_check(self):
        with patch("petfit_docker.cli.check_docker", side_effect=SystemExit("docker failed")):
            with patch("petfit_docker.cli.ensure_image_ready") as ensure_image:
                with self.assertRaises(SystemExit) as caught:
                    main([])

        ensure_image.assert_not_called()
        self.assertEqual(str(caught.exception), "docker failed")

    def test_main_dry_run_skips_docker_and_image_checks(self):
        with patch("petfit_docker.cli.check_docker") as docker_check:
            with patch("petfit_docker.cli.ensure_image_ready") as ensure_image:
                with self.assertRaises(SystemExit) as caught:
                    main(["--dry-run"])

        docker_check.assert_not_called()
        ensure_image.assert_not_called()
        self.assertIn("bids_dir", str(caught.exception))

    def test_main_skip_image_check_still_checks_docker(self):
        with patch("petfit_docker.cli.check_docker") as docker_check:
            with patch("petfit_docker.cli.ensure_image_ready") as ensure_image:
                with self.assertRaises(SystemExit) as caught:
                    main(["--skip-image-check"])

        docker_check.assert_called_once()
        ensure_image.assert_not_called()
        self.assertIn("bids_dir", str(caught.exception))

    def test_missing_image_prompts_and_defers_pull_to_memory_probe(self):
        with patch("petfit_docker.cli.image_exists", return_value=False):
            with patch("builtins.input", return_value="y"):
                with patch("sys.stdout", new_callable=StringIO) as stdout:
                    maybe_pull_image("mathesong/petfit:latest")

        self.assertIn("Downloading. This may take a while...", stdout.getvalue())

    def test_check_memory_reads_container_memory(self):
        result = subprocess.CompletedProcess(
            [
                "docker",
                "run",
                "--rm",
                "--platform",
                "linux/amd64",
                "--entrypoint=free",
                "mathesong/petfit:latest",
                "-m",
            ],
            0,
            stdout=b"              total        used        free\nMem:           15999        1000       14999\n",
        )

        with patch("petfit_docker.cli.subprocess.run", return_value=result) as run:
            self.assertEqual(check_memory("mathesong/petfit:latest"), 15999)
        run.assert_called_once_with(
            [
                "docker",
                "run",
                "--rm",
                "--platform",
                "linux/amd64",
                "--entrypoint=free",
                "mathesong/petfit:latest",
                "-m",
            ],
            stdout=subprocess.PIPE,
        )

    def test_platform_can_be_disabled_for_native_multiarch_images(self):
        result = subprocess.CompletedProcess(
            ["docker", "run", "--rm", "--entrypoint=free", "custom/petfit:arm64", "-m"],
            0,
            stdout=b"Mem:           32000        1000       31000\n",
        )

        with patch("petfit_docker.cli.subprocess.run", return_value=result) as run:
            self.assertEqual(check_memory("custom/petfit:arm64", platform=None), 32000)

        run.assert_called_once_with(
            ["docker", "run", "--rm", "--entrypoint=free", "custom/petfit:arm64", "-m"],
            stdout=subprocess.PIPE,
        )

    def test_failed_memory_probe_exits_without_traceback(self):
        with patch("petfit_docker.cli.maybe_pull_image"):
            with patch("petfit_docker.cli.check_memory", return_value=-1):
                with patch("sys.stderr", new_callable=StringIO) as stderr:
                    with self.assertRaises(SystemExit) as caught:
                        ensure_image_ready("mathesong/petfit:latest")

        self.assertIn("Could not detect memory capacity", stderr.getvalue())
        self.assertEqual(str(caught.exception), "Do you have permission to run docker?")


class ExternalFileTests(unittest.TestCase):
    """--config-file and --regions-file mount a single host file into the image."""

    @staticmethod
    def _dataset(root):
        bids = root / "bids"
        derivatives = root / "derivatives"
        bids.mkdir()
        return bids, derivatives

    def test_config_file_is_mounted_and_passed_to_modelling(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids, derivatives = self._dataset(root)
            config = root / "shared_config.json"
            config.write_text("{}")

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "modelling_ref",
                    "--config-file",
                    str(config),
                    "--automatic",
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn(f"{abs_path(config)}:/data/config.json:ro", command)
            flag_index = command.index("--config_file")
            self.assertEqual(command[flag_index + 1], "/data/config.json")
            self.assertNotIn("--regions_file", command)

    def test_regions_file_is_mounted_and_passed_to_regiondef(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids, derivatives = self._dataset(root)
            regions = root / "petfit_regions.tsv"
            regions.write_text("RegionName\tfolder\tdescription\tConstituentRegion\n")

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "regiondef",
                    "--regions-file",
                    str(regions),
                    "--automatic",
                    "--no-tty",
                    "--dry-run",
                ]
            )

            command = build_docker_command(opts)

            self.assertIn(f"{abs_path(regions)}:/data/petfit_regions.tsv:ro", command)
            flag_index = command.index("--regions_file")
            self.assertEqual(command[flag_index + 1], "/data/petfit_regions.tsv")
            self.assertNotIn("--config_file", command)

    def test_file_for_the_other_app_is_ignored(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids, derivatives = self._dataset(root)
            config = root / "shared_config.json"
            config.write_text("{}")
            regions = root / "petfit_regions.tsv"
            regions.write_text("RegionName\n")

            regiondef = build_docker_command(
                _parser().parse_args(
                    [
                        str(bids),
                        str(derivatives),
                        "participant",
                        "--app",
                        "regiondef",
                        "--config-file",
                        str(config),
                        "--regions-file",
                        str(regions),
                        "--no-tty",
                        "--dry-run",
                    ]
                )
            )

            self.assertNotIn("--config_file", regiondef)
            self.assertIn("--regions_file", regiondef)
            self.assertNotIn(f"{abs_path(config)}:/data/config.json:ro", regiondef)

            modelling = build_docker_command(
                _parser().parse_args(
                    [
                        str(bids),
                        str(derivatives),
                        "participant",
                        "--app",
                        "modelling_plasma",
                        "--config-file",
                        str(config),
                        "--regions-file",
                        str(regions),
                        "--no-tty",
                        "--dry-run",
                    ]
                )
            )

            self.assertIn("--config_file", modelling)
            self.assertNotIn("--regions_file", modelling)
            self.assertNotIn(f"{abs_path(regions)}:/data/petfit_regions.tsv:ro", modelling)

    def test_missing_external_file_exits_before_docker_creates_a_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids, derivatives = self._dataset(root)
            missing = root / "typo_config.json"

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "modelling_plasma",
                    "--config-file",
                    str(missing),
                    "--no-tty",
                    "--dry-run",
                ]
            )

            with self.assertRaises(SystemExit) as caught:
                build_docker_command(opts)

            self.assertIn("--config-file does not exist", str(caught.exception))
            self.assertFalse(missing.exists())

    def test_directory_passed_as_external_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids, derivatives = self._dataset(root)
            not_a_file = root / "configs"
            not_a_file.mkdir()

            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    "modelling_plasma",
                    "--config-file",
                    str(not_a_file),
                    "--no-tty",
                    "--dry-run",
                ]
            )

            with self.assertRaises(SystemExit) as caught:
                build_docker_command(opts)

            self.assertIn("--config-file is not a file", str(caught.exception))


class RunMergingTests(unittest.TestCase):
    """--no-merge-runs reaches the regiondef step, and only that step."""

    @staticmethod
    def _dataset(root):
        bids = root / "bids"
        derivatives = root / "derivatives"
        bids.mkdir()
        return bids, derivatives

    def _command(self, app, extra):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bids, derivatives = self._dataset(root)
            opts = _parser().parse_args(
                [
                    str(bids),
                    str(derivatives),
                    "participant",
                    "--app",
                    app,
                    "--automatic",
                    "--no-tty",
                    "--dry-run",
                ]
                + extra
            )
            return build_docker_command(opts)

    def test_runs_are_merged_by_default(self):
        command = self._command("regiondef", [])

        self.assertTrue(_parser().parse_args([]).merge_runs)
        self.assertNotIn("--no_merge_runs", command)

    def test_no_merge_runs_is_passed_to_regiondef(self):
        command = self._command("regiondef", ["--no-merge-runs"])

        self.assertIn("--no_merge_runs", command)

    def test_no_merge_runs_is_ignored_for_modelling(self):
        # Run merging is decided in region definition and is then a property of
        # the combined TACs; passing it here would suggest otherwise.
        command = self._command("modelling_plasma", ["--no-merge-runs"])

        self.assertNotIn("--no_merge_runs", command)


if __name__ == "__main__":
    unittest.main()
