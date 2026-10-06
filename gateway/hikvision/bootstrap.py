from __future__ import annotations

import json
import os
import pathlib
import sys
import threading
import time
from datetime import datetime, timezone

import agent
import common
from common import CONFIG_PATH, APP_DIR, CloudClient, GatewayConfig, HikvisionClient, log
from self_update import CHECK_INTERVAL_SECONDS, maybe_auto_update

# Evergreen release: every future Gateway release must either bump x.y.z or the
# final numeric build revision (e.g. +evergreen-2) so installed clients can order
# releases without human intervention.
GATEWAY_VERSION = "1.4.0+evergreen-1"
common.GATEWAY_VERSION = GATEWAY_VERSION

HEALTH_PATH = APP_DIR / "gateway-health.json"
HEALTH_INTERVAL_SECONDS = 10

_original_cloud_call = CloudClient.call
_next_update_check = 0.0


def _installed_gateway_path() -> pathlib.Path:
    if getattr(sys, "frozen", False):
        return pathlib.Path(sys.executable).resolve()
    return pathlib.Path(__file__).resolve()


def _atomic_json_write(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
    os.replace(temp, path)


def _write_health() -> None:
    _atomic_json_write(
        HEALTH_PATH,
        {
            "status": "healthy",
            "version": GATEWAY_VERSION,
            "pid": os.getpid(),
            "healthy_at": datetime.now(timezone.utc).isoformat(),
        },
    )


def _health_loop() -> None:
    while True:
        try:
            _write_health()
        except Exception as exc:
            log(f"health_marker_error={type(exc).__name__}:{str(exc)[:200]}")
        time.sleep(HEALTH_INTERVAL_SECONDS)


def _start_health_monitor_after_live_probe() -> None:
    """Publish local health only after recorder + cloud authentication works."""
    if not CONFIG_PATH.exists():
        return
    cfg = GatewayConfig.load()
    HikvisionClient(cfg).device_info()
    ping = CloudClient(cfg).call("ping")
    if not ping.get("ok"):
        raise RuntimeError("cloud_health_probe_failed")
    _write_health()
    threading.Thread(
        target=_health_loop,
        name="zhirox-gateway-health-marker",
        daemon=True,
    ).start()


def _patched_cloud_call(self, action: str, *args, **kwargs):
    global _next_update_check
    # Claim is only called between jobs. Checking here guarantees an update can
    # never interrupt capture, transcoding, upload or an attempt heartbeat.
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
            # Update failure never stops the working Gateway. It will try again
            # on the next interval after keeping the current known-good binary.
            log(f"auto_update_error={type(exc).__name__}:{str(exc)[:300]}")
    return _original_cloud_call(self, action, *args, **kwargs)


def preflight_update() -> int:
    if not CONFIG_PATH.exists():
        return 2
    # A staged binary proves that it can authenticate to the same recorder and
    # cloud, but it must not report the new version as installed until atomic
    # replacement succeeds.
    report_version = os.environ.get("ZHIROX_PREFLIGHT_REPORT_VERSION", "").strip()
    if report_version:
        common.GATEWAY_VERSION = report_version
    cfg = GatewayConfig.load()
    HikvisionClient(cfg).device_info()
    ping = CloudClient(cfg).call("ping")
    return 0 if ping.get("ok") else 3


def verify_ocr_fixture(path: str) -> int:
    from datetime import timezone as dt_timezone
    from osd_time import ocr_image, dates_in_text

    result = dates_in_text(ocr_image(pathlib.Path(path)), dt_timezone.utc, "YMD")
    return 0 if result else 1


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--preflight-update":
        return preflight_update()
    if len(sys.argv) == 3 and sys.argv[1] == "--verify-ocr-fixture":
        return verify_ocr_fixture(sys.argv[2])

    CloudClient.call = _patched_cloud_call
    log(f"gateway_bootstrap version={GATEWAY_VERSION} auto_update=evergreen")

    # The updater waits for two health-marker writes after restart. This live
    # probe proves the new executable can load config and authenticate to NVR +
    # cloud; a local heartbeat then proves it remained alive before old files are
    # considered safely replaced.
    try:
        _start_health_monitor_after_live_probe()
    except Exception as exc:
        log(f"startup_health_probe_error={type(exc).__name__}:{str(exc)[:300]}")

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
