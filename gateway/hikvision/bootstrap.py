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
import maintenance
from common import CONFIG_PATH, APP_DIR, CloudClient, GatewayConfig, HikvisionClient, log
from self_update import CHECK_INTERVAL_SECONDS, UPDATE_PROTOCOL
from update_policy import maybe_auto_update

# Evergreen release: future Gateway releases must bump x.y.z or the final
# numeric build revision (for example +evergreen-2) so clients can order them.
GATEWAY_VERSION = "1.4.2+evergreen-1"
common.GATEWAY_VERSION = GATEWAY_VERSION

HEALTH_PATH = APP_DIR / "gateway-health.json"
HEALTH_INTERVAL_SECONDS = 10
HEALTH_PROBE_RETRY_SECONDS = 5

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
            "update_protocol": UPDATE_PROTOCOL,
            "pid": os.getpid(),
            "healthy_at": datetime.now(timezone.utc).isoformat(),
        },
    )


def _health_monitor_loop() -> None:
    """Retry the live NVR/cloud probe until it succeeds, then heartbeat locally.

    A short network outage exactly at restart must not make a healthy update look
    broken and trigger a false rollback. No healthy marker is written until both
    the recorder and cloud have authenticated successfully at least once.
    """
    while True:
        try:
            if not CONFIG_PATH.exists():
                raise RuntimeError("configuration_missing")
            cfg = GatewayConfig.load()
            HikvisionClient(cfg).device_info()
            ping = CloudClient(cfg).call("ping")
            if not ping.get("ok"):
                raise RuntimeError("cloud_health_probe_failed")
            _write_health()
            log("startup_health_probe=healthy")
            break
        except Exception as exc:
            log(f"startup_health_probe_retry={type(exc).__name__}:{str(exc)[:240]}")
            time.sleep(HEALTH_PROBE_RETRY_SECONDS)

    while True:
        try:
            _write_health()
        except Exception as exc:
            log(f"health_marker_error={type(exc).__name__}:{str(exc)[:200]}")
        time.sleep(HEALTH_INTERVAL_SECONDS)


def _start_health_monitor() -> None:
    threading.Thread(
        target=_health_monitor_loop,
        name="zhirox-gateway-health-monitor",
        daemon=True,
    ).start()


def _patched_cloud_call(self, action: str, *args, **kwargs):
    global _next_update_check
    # Claim is only called between jobs, so an update never interrupts capture,
    # transcoding, upload, or an active job lease heartbeat.
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
            # Update failure never stops the working Gateway. It retries on a
            # later interval while the known-good binary continues processing.
            log(f"auto_update_error={type(exc).__name__}:{str(exc)[:300]}")
    return _original_cloud_call(self, action, *args, **kwargs)


def preflight_update() -> int:
    if not CONFIG_PATH.exists():
        return 2
    # A staged binary proves that it can authenticate to the same recorder and
    # cloud, but reports the installed version until replacement succeeds.
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
    gateway_path = _installed_gateway_path()
    log(
        f"gateway_bootstrap version={GATEWAY_VERSION} "
        f"update_protocol={UPDATE_PROTOCOL} auto_update=evergreen"
    )
    maintenance.start(gateway_path, log)
    _start_health_monitor()
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
