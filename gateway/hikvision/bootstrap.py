from __future__ import annotations

import os
import pathlib
import sys
import time

import agent
import common
from common import CONFIG_PATH, APP_DIR, CloudClient, GatewayConfig, HikvisionClient, log
from self_update import CHECK_INTERVAL_SECONDS, maybe_auto_update

# This is the installed product version used for cloud heartbeats and release
# comparison. Future Gateway changes must bump this value before publishing.
GATEWAY_VERSION = "1.3.4+auto-update-1"
common.GATEWAY_VERSION = GATEWAY_VERSION

_original_cloud_call = CloudClient.call
_next_update_check = 0.0


def _installed_gateway_path() -> pathlib.Path:
    if getattr(sys, "frozen", False):
        return pathlib.Path(sys.executable).resolve()
    return pathlib.Path(__file__).resolve()


def _patched_cloud_call(self, action: str, *args, **kwargs):
    global _next_update_check
    # Claim is only called between jobs. Checking here guarantees an update can
    # never interrupt a capture, transcode, upload or attempt heartbeat.
    if action == "claim" and time.monotonic() >= _next_update_check:
        _next_update_check = time.monotonic() + CHECK_INTERVAL_SECONDS
        try:
            if maybe_auto_update(
                GATEWAY_VERSION,
                _installed_gateway_path(),
                APP_DIR,
                log,
            ):
                log("auto_update_handoff=started; gateway exiting cleanly")
                raise SystemExit(0)
        except SystemExit:
            raise
        except Exception as exc:
            log(f"auto_update_error={type(exc).__name__}:{str(exc)[:300]}")
    return _original_cloud_call(self, action, *args, **kwargs)


def preflight_update() -> int:
    if not CONFIG_PATH.exists():
        return 2
    # A staged binary proves that it can authenticate to the same recorder and
    # cloud, but it must not report the new version as installed until the atomic
    # replacement actually succeeds.
    report_version = os.environ.get("ZHIROX_PREFLIGHT_REPORT_VERSION", "").strip()
    if report_version:
        common.GATEWAY_VERSION = report_version
    cfg = GatewayConfig.load()
    HikvisionClient(cfg).device_info()
    ping = CloudClient(cfg).call("ping")
    return 0 if ping.get("ok") else 3


def verify_ocr_fixture(path: str) -> int:
    from datetime import timezone
    from osd_time import ocr_image, dates_in_text

    result = dates_in_text(ocr_image(pathlib.Path(path)), timezone.utc, "YMD")
    return 0 if result else 1


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--preflight-update":
        return preflight_update()
    if len(sys.argv) == 3 and sys.argv[1] == "--verify-ocr-fixture":
        return verify_ocr_fixture(sys.argv[2])

    CloudClient.call = _patched_cloud_call
    log(f"gateway_bootstrap version={GATEWAY_VERSION} auto_update=enabled")
    agent.main()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        log(f"bootstrap_error={type(exc).__name__}:{str(exc)[:500]}")
        raise SystemExit(1)
