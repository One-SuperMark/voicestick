import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "build-macos.sh"
HELPERS = SCRIPT.read_text().split("# BEGIN LOCAL DEVELOPMENT VERSION HELPERS\n", 1)[1].split(
    "# END LOCAL DEVELOPMENT VERSION HELPERS", 1
)[0]


class LocalDevelopmentVersionTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.build_directory = Path(self.temporary_directory.name)
        self.state_path = self.build_directory / ".development-version-state"

    def run_helper(self, command, baseline="0.3.6", extra_arguments=()):
        return subprocess.run(
            ["bash", "-c", "set -euo pipefail\n" + HELPERS + "\n" + command,
             "development-version-test", baseline, str(self.state_path), *extra_arguments],
            check=False,
            capture_output=True,
            text=True,
        )

    def next_revision(self, baseline="0.3.6"):
        return self.run_helper('next_development_revision "$1" "$2"', baseline)

    def test_first_candidate_is_one_without_consuming_it(self):
        for _ in range(2):
            result = self.next_revision()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "1\n")
            self.assertFalse(self.state_path.exists())

    def test_successful_state_save_increments_next_candidate(self):
        result = self.run_helper('save_development_revision "$1" "$3" "$2"', extra_arguments=("1",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state_path.read_text(), "0.3.6 1\n")
        self.assertEqual(self.next_revision().stdout, "2\n")
        self.assertEqual(self.state_path.read_text(), "0.3.6 1\n")

    def test_changed_baseline_restarts_at_one(self):
        self.state_path.write_text("0.3.6 21\n")
        result = self.next_revision("0.3.7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "1\n")
        self.assertEqual(self.state_path.read_text(), "0.3.6 21\n")

    def test_malformed_state_is_rejected_without_overwrite(self):
        malformed_states = [
            "", "0.3 1\n", "0.3.6.1 1\n", "0.3.6 0\n", "0.3.6 -1\n",
            "0.3.6 01\n", "0.3.6 1000000000\n", "0.3.6 2 extra\n", "0.3.6 2",
            "0.3.6 2\n\n", "0.3.6 2\0\n",
            "0.3.6 2\n0.3.6 3\n", "0.3.6 $(printf unsafe)\n", "x" * 129,
        ]
        for state in malformed_states:
            with self.subTest(state=state):
                self.state_path.write_text(state)
                result = self.next_revision()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.state_path.read_text(), state)

    def test_non_regular_state_is_rejected(self):
        self.state_path.mkdir()
        self.assertNotEqual(self.next_revision().returncode, 0)
        self.state_path.rmdir()
        target = self.build_directory / "target-state"
        target.write_text("0.3.6 3\n")
        self.state_path.symlink_to(target)
        self.assertNotEqual(self.next_revision().returncode, 0)
        self.assertEqual(target.read_text(), "0.3.6 3\n")

    def test_exhausted_counter_is_rejected_but_new_baseline_can_reset(self):
        self.state_path.write_text("0.3.6 999999999\n")
        self.assertNotEqual(self.next_revision().returncode, 0)
        result = self.next_revision("0.3.7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "1\n")

    def test_state_save_atomically_replaces_previous_value(self):
        self.state_path.write_text("0.3.6 1\n")
        result = self.run_helper('save_development_revision "$1" "$3" "$2"', extra_arguments=("2",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state_path.read_text(), "0.3.6 2\n")
        self.assertEqual(list(self.build_directory.glob(".development-version-state.*")), [])

    def test_failed_build_does_not_consume_candidate(self):
        self.state_path.write_text("0.3.6 4\n")
        result = self.run_helper('revision="$(next_development_revision "$1" "$2")"\nexit 17')
        self.assertEqual(result.returncode, 17)
        self.assertEqual(self.state_path.read_text(), "0.3.6 4\n")
        self.assertEqual(self.next_revision().stdout, "5\n")

    def test_exit_trap_releases_only_the_acquired_empty_lock(self):
        lock_path = self.build_directory / ".development-version.lock"
        result = self.run_helper(
            'DEVELOPMENT_LOCK_DIR="$3"\nmkdir "$DEVELOPMENT_LOCK_DIR"\n'
            'DEVELOPMENT_LOCK_ACQUIRED=1\ntrap release_development_lock EXIT\nexit 17',
            extra_arguments=(str(lock_path),),
        )
        self.assertEqual(result.returncode, 17)
        self.assertFalse(lock_path.exists())
        lock_path.mkdir()
        result = self.run_helper('DEVELOPMENT_LOCK_DIR="$3"\nrelease_development_lock',
                                 extra_arguments=(str(lock_path),))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(lock_path.exists())


if __name__ == "__main__":
    unittest.main()
