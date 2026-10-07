from __future__ import annotations

import os
import pathlib
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parent
SETUP_EXE = ROOT / "dist" / "zhirox-hikvision-setup.exe"


@unittest.skipUnless(os.name == "nt", "frozen Setup smoke test is Windows-only")
class FrozenSetupSmokeTest(unittest.TestCase):
    def test_setup_executable_starts_and_self_tests(self) -> None:
        self.assertTrue(SETUP_EXE.exists(), f"Setup EXE missing: {SETUP_EXE}")
        result = subprocess.run(
            [str(SETUP_EXE), "--self-test"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        output = (result.stdout or "") + (result.stderr or "")
        self.assertEqual(
            result.returncode,
            0,
            f"Frozen Setup failed to start/self-test. Output:\n{output}",
        )
        self.assertIn("setup_self_test=ok", output)


if __name__ == "__main__":
    unittest.main()
