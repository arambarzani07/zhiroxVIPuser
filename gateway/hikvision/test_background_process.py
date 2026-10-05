"""Verify media helpers do not allocate Windows console windows."""
import os
import subprocess
import sys
import unittest
from unittest.mock import patch
from common import run_background


class BackgroundProcessTest(unittest.TestCase):
    def test_windows_flags_preserve_other_options(self):
        with patch("common.os.name", "nt"), patch.object(subprocess, "CREATE_NO_WINDOW", 0x08000000, create=True), patch("common.subprocess.run") as run:
            run_background(["media.exe"], capture_output=True, timeout=20, creationflags=0x200)
        self.assertEqual(run.call_args.kwargs["creationflags"], 0x08000200)
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertTrue(run.call_args.kwargs["capture_output"])
        self.assertEqual(run.call_args.kwargs["timeout"], 20)

    @unittest.skipUnless(os.name == "nt", "requires native Windows")
    def test_child_has_no_console_window(self):
        result = run_background([sys.executable, "-c",
            "import ctypes; print(int(bool(ctypes.windll.kernel32.GetConsoleWindow())))"],
            capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), b"0")


if __name__ == "__main__":
    unittest.main()
