import tempfile
import unittest
import os
import subprocess
from pathlib import Path
from unittest.mock import patch

import check_separator_dependencies as dependencies
import separator_ci_changes as changes


class DependencyLockTests(unittest.TestCase):
    def test_checked_in_lock_matches_inputs_and_platform(self):
        pins = dependencies.validate_lock(dependencies.HELPER)
        self.assertEqual(pins["audio-separator"], "0.44.2")
        dependencies.validate_platform(dependencies.HELPER, "Darwin", "arm64", "3.14.5")

    def test_wrong_python_or_architecture_fails(self):
        for platform in [("Darwin", "arm64", "3.13.0"), ("Darwin", "x86_64", "3.14.5")]:
            with self.subTest(platform=platform), self.assertRaisesRegex(ValueError, "PYTHON_BIN"):
                dependencies.validate_platform(dependencies.HELPER, *platform)

    def test_input_edit_requires_lock_refresh(self):
        with tempfile.TemporaryDirectory() as root:
            helper = Path(root)
            for name in (*dependencies.INPUTS, dependencies.LOCK_NAME):
                (helper / name).write_bytes((dependencies.HELPER / name).read_bytes())
            with (helper / "requirements.txt").open("a") as output:
                output.write("new-package==1.0\n")
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                dependencies.validate_lock(helper)

    def test_exact_environment_rejects_missing_extra_and_wrong_versions(self):
        expected = {"package": "1.0"}
        dependencies.validate_environment(expected, expected)
        for installed in [{}, {"package": "2.0"}, {"package": "1.0", "extra": "1.0"}]:
            with self.subTest(installed=installed), self.assertRaisesRegex(ValueError, "does not match"):
                dependencies.validate_environment(expected, installed)

    def test_unpinned_duplicate_and_url_requirements_fail(self):
        for content in ["package>=1.0", "package @ https://example.com/package.whl", "package==1\nPackage==1"]:
            with tempfile.TemporaryDirectory() as root:
                path = Path(root) / "lock"
                path.write_text(content)
                with self.assertRaises(ValueError):
                    dependencies.read_pins(path)

    def test_failed_install_stops_before_packaging(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / "scripts").mkdir()
            (root / "JammLabSeparatorHelper").mkdir()
            build_script = root / "scripts/build_separator_helper.sh"
            build_script.write_bytes((dependencies.HELPER.parent / "scripts/build_separator_helper.sh").read_bytes())
            (root / "JammLabSeparatorHelper" / dependencies.LOCK_NAME).write_text("pip==26.1.2\n")
            fake_python = root / "fake-python"
            fake_python.write_text('''#!/bin/bash
if [[ "$1" == *check_separator_dependencies.py ]]; then exit 0; fi
if [[ "$1" == -m && "$2" == venv ]]; then
  mkdir -p "$4/bin"
  printf '#!/bin/bash\\nexit 23\\n' > "$4/bin/python"
  chmod +x "$4/bin/python"
  exit 0
fi
exit 99
''')
            fake_python.chmod(0o755)
            result = subprocess.run(["bash", str(build_script)], env={**os.environ, "PYTHON_BIN": str(fake_python)},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertFalse((root / "build/JammLabSeparatorHelper/dist").exists())


class ChangeSelectionTests(unittest.TestCase):
    def test_helper_and_workflow_changes_require_packaging(self):
        for path in ["JammLabSeparatorHelper/.python-version", "JammLabSeparatorHelper/runner.py",
                     ".github/workflows/ci.yml", "scripts/build_separator_helper.sh",
                     "scripts/test_separator_dependencies.py", "scripts/package_dmg.sh",
                     "JammLab.xcodeproj/project.pbxproj", "JammLabStemHelper/main.swift",
                     "Configurations/CI.xcconfig", "JammLab/JammLab.Release.entitlements"]:
            self.assertTrue(changes.needs_full_check("pull_request", "refs/pull/1/merge", [path]), path)

    def test_ui_only_change_skips_packaging(self):
        self.assertFalse(changes.needs_full_check("pull_request", "refs/pull/1/merge", ["JammLab/Views/ContentView.swift"]))

    def test_tag_and_manual_runs_always_validate(self):
        self.assertTrue(changes.needs_full_check("push", "refs/tags/v1.2.3", []))
        self.assertTrue(changes.needs_full_check("workflow_dispatch", "refs/heads/main", []))

    def test_diff_failure_is_not_treated_as_no_changes(self):
        import subprocess
        with patch.object(changes.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                changes.changed_paths("push", {"before": "a" * 40, "after": "b" * 40})

    def test_rename_out_of_helper_directory_still_requires_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.invalid")
            (root / "JammLabSeparatorHelper").mkdir()
            (root / "JammLabSeparatorHelper/input.txt").write_text("packaging input\n")
            git("add", ".")
            git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "initial")
            before = git("rev-parse", "HEAD")
            git("mv", "JammLabSeparatorHelper/input.txt", "elsewhere.txt")
            git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "rename")
            after = git("rev-parse", "HEAD")
            previous = Path.cwd()
            try:
                os.chdir(root)
                paths = changes.changed_paths("push", {"before": before, "after": after})
            finally:
                os.chdir(previous)
            self.assertTrue(changes.needs_full_check("push", "refs/heads/test", paths))


if __name__ == "__main__":
    unittest.main()
