from __future__ import annotations

import json
import pathlib
import tempfile
import time
import unittest
from datetime import datetime
from unittest import mock

import bootstrap
import runtime_hardening
from common import GatewayConfig


class RuntimeResilienceTest(unittest.TestCase):
    def test_atomic_config_save_never_leaves_partial_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = pathlib.Path(tmp)
            config = app / "config.json"
            old = runtime_hardening.CONFIG_PATH
            old_app = runtime_hardening.APP_DIR
            try:
                runtime_hardening.APP_DIR = app
                runtime_hardening.CONFIG_PATH = config
                cfg = GatewayConfig("192.168.1.2", "admin", "secret", "t" * 40)
                with mock.patch.object(
                    runtime_hardening,
                    "protect_secret",
                    side_effect=lambda value: "enc:" + value,
                ):
                    runtime_hardening.save_config_atomic(cfg)
                payload = json.loads(config.read_text(encoding="utf-8"))
                self.assertEqual(payload["nvr_host"], "192.168.1.2")
                self.assertEqual(payload["nvr_password_dpapi"], "enc:secret")
                self.assertEqual(payload["gateway_token_dpapi"], "enc:" + ("t" * 40))
                self.assertFalse((app / "config.json.new").exists())
            finally:
                runtime_hardening.CONFIG_PATH = old
                runtime_hardening.APP_DIR = old_app

    def test_lease_heartbeat_does_not_refresh_worker_progress(self):
        original_call = bootstrap._original_cloud_call
        old_progress = bootstrap._last_worker_progress
        old_next = bootstrap._next_update_check
        try:
            bootstrap._last_worker_progress = time.monotonic() - 100
            before = bootstrap._last_worker_progress
            bootstrap._original_cloud_call = lambda _self, action, *a, **k: {"ok": True}
            result = bootstrap._patched_cloud_call(object(), "heartbeat_job")
            self.assertEqual(result, {"ok": True})
            self.assertEqual(bootstrap._last_worker_progress, before)

            bootstrap._patched_cloud_call(object(), "complete")
            self.assertGreater(bootstrap._last_worker_progress, before)
        finally:
            bootstrap._original_cloud_call = original_call
            bootstrap._last_worker_progress = old_progress
            bootstrap._next_update_check = old_next

    def test_worker_progress_age_is_non_negative(self):
        old_progress = bootstrap._last_worker_progress
        try:
            bootstrap._last_worker_progress = time.monotonic() - 5
            self.assertGreaterEqual(bootstrap._worker_progress_age(), 4)
        finally:
            bootstrap._last_worker_progress = old_progress

    def test_nvr_clock_drift_measurement_is_read_only(self):
        class Response:
            status_code = 200
            def raise_for_status(self):
                return None

        class Session:
            def __init__(self):
                self.calls = []
            def get(self, url, timeout):
                self.calls.append((url, timeout))
                now = datetime.now(runtime_hardening.BAGHDAD_TZ).replace(microsecond=0)
                Response.content = (
                    "<?xml version='1.0' encoding='UTF-8'?>"
                    "<Time><localTime>" + now.isoformat() + "</localTime></Time>"
                ).encode("utf-8")
                return Response()

        class Hik:
            host = "http://192.168.1.2"
            session = Session()

        drift = runtime_hardening.measure_nvr_clock_drift(Hik())
        self.assertLessEqual(drift, 2.0)
        self.assertEqual(len(Hik.session.calls), 1)
        self.assertIn("/ISAPI/System/time", Hik.session.calls[0][0])


if __name__ == "__main__":
    unittest.main()
