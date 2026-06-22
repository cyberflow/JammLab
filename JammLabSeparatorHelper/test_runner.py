import contextlib
import io
import logging
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import runner


class RunnerTests(unittest.TestCase):
    def test_parse_log_level_accepts_named_levels(self):
        self.assertEqual(runner.parse_log_level("INFO"), logging.INFO)
        self.assertEqual(runner.parse_log_level("debug"), logging.DEBUG)

    def test_parse_log_level_accepts_numeric_levels(self):
        self.assertEqual(runner.parse_log_level("20"), logging.INFO)

    def test_parse_log_level_rejects_unknown_values(self):
        with self.assertRaises(SystemExit) as context:
            runner.parse_log_level("verbose")

        self.assertEqual(str(context.exception), "Unsupported --log_level: verbose")

    def test_copy_seed_model_cache_copies_missing_files(self):
        with tempfile.TemporaryDirectory() as seed_root, tempfile.TemporaryDirectory() as model_root:
            seed_dir = Path(seed_root)
            model_dir = Path(model_root)
            (seed_dir / "nested").mkdir()
            (seed_dir / "download_checks.json").write_text("{}", encoding="utf-8")
            (seed_dir / "nested" / "htdemucs.yaml").write_text("model", encoding="utf-8")

            copied = runner.copy_seed_model_cache(model_dir, seed_dir)

            self.assertEqual(copied, 2)
            self.assertEqual((model_dir / "download_checks.json").read_text(encoding="utf-8"), "{}")
            self.assertEqual((model_dir / "nested" / "htdemucs.yaml").read_text(encoding="utf-8"), "model")

    def test_copy_seed_model_cache_does_not_overwrite_existing_files(self):
        with tempfile.TemporaryDirectory() as seed_root, tempfile.TemporaryDirectory() as model_root:
            seed_dir = Path(seed_root)
            model_dir = Path(model_root)
            (seed_dir / "htdemucs.yaml").write_text("seed", encoding="utf-8")
            (model_dir / "htdemucs.yaml").write_text("existing", encoding="utf-8")

            copied = runner.copy_seed_model_cache(model_dir, seed_dir)

            self.assertEqual(copied, 0)
            self.assertEqual((model_dir / "htdemucs.yaml").read_text(encoding="utf-8"), "existing")

    def test_missing_required_model_files_detects_demucs_weights(self):
        with tempfile.TemporaryDirectory() as model_root:
            model_dir = Path(model_root)
            (model_dir / "htdemucs_6s.yaml").write_text("model", encoding="utf-8")

            missing = runner.missing_required_model_files(model_dir, "htdemucs_6s.yaml")

            self.assertEqual(missing, ["5c90dfd2-34c22ccb.th"])

    def test_ensure_required_model_files_rejects_incomplete_cache(self):
        with tempfile.TemporaryDirectory() as model_root:
            model_dir = Path(model_root)
            (model_dir / "htdemucs_6s.yaml").write_text("model", encoding="utf-8")

            with self.assertRaises(SystemExit) as context:
                runner.ensure_required_model_files(model_dir, "htdemucs_6s.yaml")

            self.assertIn("htdemucs_6s.yaml", str(context.exception))
            self.assertIn("5c90dfd2-34c22ccb.th", str(context.exception))

    def test_validate_model_cache_accepts_complete_cache(self):
        with tempfile.TemporaryDirectory() as model_root:
            model_dir = Path(model_root)
            (model_dir / "htdemucs_6s.yaml").write_text("model", encoding="utf-8")
            (model_dir / "5c90dfd2-34c22ccb.th").write_text("weights", encoding="utf-8")
            args = runner.parse_args([
                "--validate_model_cache",
                "htdemucs_6s.yaml",
                "--model_file_dir",
                str(model_dir),
            ])

            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(runner.validate_model_cache(args), 0)

    def test_configure_compute_device_accepts_cpu_and_auto(self):
        runner.configure_compute_device("cpu")
        runner.configure_compute_device("auto")

    def test_configure_compute_device_rejects_unknown_values(self):
        with self.assertRaises(SystemExit) as context:
            runner.configure_compute_device("mps")

        self.assertEqual(str(context.exception), "Unsupported --compute_device: mps")


if __name__ == "__main__":
    unittest.main()
