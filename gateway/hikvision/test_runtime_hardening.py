import pathlib
import tempfile
import unittest
from unittest import mock

import runtime_hardening


class RuntimeHardeningTest(unittest.TestCase):
    def test_recover_config_from_known_good_backup(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            config = root / "config.json"
            backup = root / "config.json.bak"
            config.write_text("corrupt", encoding="utf-8")
            backup.write_text("known-good", encoding="utf-8")
            logs = []

            def usable(path):
                return path == backup

            with mock.patch.object(runtime_hardening, "CONFIG_PATH", config), \
                 mock.patch.object(runtime_hardening, "CONFIG_BACKUP_PATH", backup), \
                 mock.patch.object(runtime_hardening, "APP_DIR", root), \
                 mock.patch.object(runtime_hardening, "_config_is_usable", side_effect=usable):
                runtime_hardening.recover_or_backup_config(logs.append)

            self.assertEqual(config.read_text(encoding="utf-8"), "known-good")
            self.assertTrue(any("config_recovered" in line for line in logs))

    def test_known_good_config_refreshes_backup_atomically(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            config = root / "config.json"
            backup = root / "config.json.bak"
            config.write_text("new-good", encoding="utf-8")
            backup.write_text("old-good", encoding="utf-8")

            with mock.patch.object(runtime_hardening, "CONFIG_PATH", config), \
                 mock.patch.object(runtime_hardening, "CONFIG_BACKUP_PATH", backup), \
                 mock.patch.object(runtime_hardening, "APP_DIR", root), \
                 mock.patch.object(runtime_hardening, "_config_is_usable", return_value=True):
                runtime_hardening.recover_or_backup_config(lambda message: None)

            self.assertEqual(backup.read_text(encoding="utf-8"), "new-good")
            self.assertFalse((root / "config.json.bak.tmp").exists())

    def test_process_job_wrapper_keeps_single_call(self):
        calls = []

        class FakeAgent:
            @staticmethod
            def process_job(*args, **kwargs):
                calls.append((args, kwargs))
                return "ok"

        logs = []
        with mock.patch.object(runtime_hardening, "keep_system_awake") as awake:
            awake.return_value.__enter__.return_value = None
            awake.return_value.__exit__.return_value = None
            runtime_hardening.wrap_process_job(FakeAgent, logs.append)
            result = FakeAgent.process_job(1, key="value")

        self.assertEqual(result, "ok")
        self.assertEqual(calls, [((1,), {"key": "value"})])
        self.assertTrue(any("sleep_guard" in line for line in logs))


if __name__ == "__main__":
    unittest.main()
