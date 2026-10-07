from __future__ import annotations

import json
import os
import pathlib
import sys
import threading
import time
from datetime import datetime, timezone
from urllib.parse import parse_qs, urlsplit

import agent
import common
import maintenance
import recording_recovery
import runtime_hardening
import transport_clock
from common import CONFIG_PATH, APP_DIR, CloudClient, GatewayConfig, HikvisionClient, log
from self_update import CHECK_INTERVAL_SECONDS as DEFAULT_UPDATE_CHECK_INTERVAL_SECONDS, UPDATE_PROTOCOL
from update_policy import maybe_auto_update

# Evergreen release: future Gateway releases must bump x.y.z or the final
# numeric build revision (for example +evergreen-2) so clients can order them.
GATEWAY_VERSION = "1.4.16+evergreen-15"
common.GATEWAY_VERSION = GATEWAY_VERSION

# Poll GitHub often enough that routine Gateway fixes arrive quickly, while the
# update handoff still occurs only between jobs and never interrupts a capture.
CHECK_INTERVAL_SECONDS = 5 * 60

HEALTH_PATH = APP_DIR / "gateway-health.json"
HEALTH_INTERVAL_SECONDS = 10
HEALTH_PROBE_RETRY_SECONDS = 5
WORKER_STALL_SECONDS = 15 * 60
WATCHDOG_INTERVAL_SECONDS = 30
CLOCK_CHECK_INTERVAL_SECONDS = 10 * 60
CLOCK_DRIFT_WARN_SECONDS = 30
MAX_BOUNDED_EXPORT_BYTES = 256 * 1024 * 1024

_original_cloud_call = CloudClient.call
_original_download_recording = HikvisionClient.download_recording
_next_update_check = 0.0
_last_worker_progress = time.monotonic()
_last_nvr_clock_drift_seconds: float | None = None
_last_nvr_clock_check_at: str | None = None


def _installed_gateway_path() -> pathlib.Path:
    if getattr(sys, "frozen", False):
        return pathlib.Path(sys.executable).resolve()
    return pathlib.Path(__file__).resolve()


def _desktop_dirs() -> list[pathlib.Path]:
    """Return normal and OneDrive-backed Desktop locations for this Windows user."""
    candidates: list[pathlib.Path] = [pathlib.Path.home() / "Desktop"]
    for key in ("USERPROFILE", "OneDrive", "OneDriveConsumer", "OneDriveCommercial"):
        root = os.environ.get(key, "").strip()
        if root:
            candidates.append(pathlib.Path(root) / "Desktop")

    result: list[pathlib.Path] = []
    seen: set[str] = set()
    for path in candidates:
        try:
            key = str(path.resolve()).casefold()
        except OSError:
            key = str(path).casefold()
        if key not in seen:
            seen.add(key)
            result.append(path)
    return result


def _cleanup_stale_setup_downloads() -> None:
    """Clean stale Gateway downloads from Desktop locations after updates settle.

    Browser-numbered copies are handled by maintenance. Windows Explorer may hide
    the final ``.bak`` extension, making ``gateway.exe.bak`` appear as
    ``gateway.exe`` with Type ``BAK File``. Those rollback backups are deleted only
    after the updater lock/journal has cleared so they can never break rollback.
    """
    if os.name != "nt":
        return
    if maintenance.update_in_progress():
        log("desktop_gateway_cleanup_deferred=update_in_progress")
        return

    for desktop in _desktop_dirs():
        for target in (desktop, desktop / "camera"):
            if not target.exists():
                continue

            removed = maintenance.cleanup_gateway_download_duplicates(target)
            backup_removed = 0
            try:
                children = list(target.iterdir())
            except OSError:
                children = []

            for candidate in children:
                try:
                    if not candidate.is_file():
                        continue
                    lowered = candidate.name.casefold()
                    if not lowered.startswith("zhirox-hikvision-"):
                        continue
                    if not lowered.endswith(".bak"):
                        continue
                    candidate.unlink(missing_ok=True)
                    backup_removed += 1
                except OSError:
                    # OneDrive or a just-finished process may hold a file briefly.
                    # Deferred cleanup retries again automatically.
                    continue

            if removed or backup_removed:
                log(
                    f"desktop_gateway_cleanup dir={target} "
                    f"duplicates={removed} backups={backup_removed}"
                )


def _desktop_cleanup_retry_loop() -> None:
    """Retry cleanup after self-update releases its rollback lock and OneDrive settles."""
    for delay_seconds in (15, 30, 60, 120, 300):
        time.sleep(delay_seconds)
        try:
            _cleanup_stale_setup_downloads()
        except Exception as exc:
            log(f"desktop_gateway_cleanup_retry_error={type(exc).__name__}:{str(exc)[:200]}")


def _start_deferred_desktop_cleanup() -> None:
    threading.Thread(
        target=_desktop_cleanup_retry_loop,
        name="zhirox-gateway-desktop-cleanup",
        daemon=True,
    ).start()


def _guarded_download_recording(
    self: HikvisionClient,
    playback_uri: str,
    output_path: pathlib.Path,
) -> str:
    """Reject HTTP 200 false-successes that contain a whole recording segment."""
    mode = _original_download_recording(self, playback_uri, output_path)
    try:
        query = parse_qs(urlsplit(playback_uri).query)
        bounded = set(query) == {"starttime", "endtime"}
    except Exception:
        bounded = False
    if (
        bounded
        and output_path.exists()
        and output_path.stat().st_size > MAX_BOUNDED_EXPORT_BYTES
    ):
        size = output_path.stat().st_size
        output_path.unlink(missing_ok=True)
        log(
            f"bounded_http_export_oversized bytes={size} "
            "forcing_bounded_fallback=true"
        )
        raise RuntimeError("download_rejected:oversized_bounded_export")
    return mode


def _atomic_json_write(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
    os.replace(temp, path)


def _worker_progress_age() -> int:
    return max(0, int(time.monotonic() - _last_worker_progress))


def _write_health() -> None:
    _atomic_json_write(
        HEALTH_PATH,
        {
            "status": "healthy",
            "version": GATEWAY_VERSION,
            "update_protocol": UPDATE_PROTOCOL,
            "pid": os.getpid(),
            "worker_progress_age_seconds": _worker_progress_age(),
            "nvr_clock_drift_seconds": _last_nvr_clock_drift_seconds,
            "nvr_clock_checked_at": _last_nvr_clock_check_at,
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


def _nvr_clock_monitor_loop() -> None:
    """Read-only clock monitoring; never changes NVR or camera settings."""
    global _last_nvr_clock_drift_seconds, _last_nvr_clock_check_at
    while True:
        try:
            if not CONFIG_PATH.exists():
                raise RuntimeError("configuration_missing")
            cfg = GatewayConfig.load()
            drift = runtime_hardening.measure_nvr_clock_drift(HikvisionClient(cfg))
            _last_nvr_clock_drift_seconds = drift
            _last_nvr_clock_check_at = datetime.now(timezone.utc).isoformat()
            if drift > CLOCK_DRIFT_WARN_SECONDS:
                log(f"nvr_clock_drift_warning seconds={drift}")
            else:
                log(f"nvr_clock_drift_ok seconds={drift}")
        except Exception as exc:
            log(f"nvr_clock_monitor_error={type(exc).__name__}:{str(exc)[:220]}")
        time.sleep(CLOCK_CHECK_INTERVAL_SECONDS)


def _start_nvr_clock_monitor() -> None:
    threading.Thread(
        target=_nvr_clock_monitor_loop,
        name="zhirox-gateway-nvr-clock-monitor",
        daemon=True,
    ).start()


def _worker_watchdog_loop() -> None:
    """Force a clean Scheduled-Task restart if the real worker becomes stuck.

    Job-lease heartbeat calls are deliberately excluded from progress so a hung
    FFmpeg/download worker cannot look healthy merely because its lease thread is
    still sending heartbeats. A normal idle Gateway calls claim every few seconds.
    """
    while True:
        time.sleep(WATCHDOG_INTERVAL_SECONDS)
        age = _worker_progress_age()
        if age > WORKER_STALL_SECONDS:
            try:
                log(f"worker_watchdog_stall seconds={age}; forcing_task_restart=true")
            finally:
                os._exit(75)


def _start_worker_watchdog() -> None:
    threading.Thread(
        target=_worker_watchdog_loop,
        name="zhirox-gateway-worker-watchdog",
        daemon=True,
    ).start()


def _patched_cloud_call(self, action: str, *args, **kwargs):
    global _next_update_check, _last_worker_progress
    if action != "heartbeat_job":
        _last_worker_progress = time.monotonic()

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

    if not runtime_hardening.acquire_single_instance():
        log("duplicate_gateway_instance=ignored")
        return 0

    _cleanup_stale_setup_downloads()
    _start_deferred_desktop_cleanup()

    runtime_hardening.recover_or_backup_config(log)
    runtime_hardening.wrap_process_job(agent, log)
    recording_recovery.install(agent, log)
    transport_clock.install(agent, HikvisionClient, log)

    CloudClient.call = _patched_cloud_call
    HikvisionClient.download_recording = _guarded_download_recording
    gateway_path = _installed_gateway_path()
    log(
        f"gateway_bootstrap version={GATEWAY_VERSION} "
        f"update_protocol={UPDATE_PROTOCOL} auto_update=evergreen "
        f"update_check_seconds={CHECK_INTERVAL_SECONDS} "
        f"worker_watchdog_seconds={WORKER_STALL_SECONDS} "
        f"clock_monitor_seconds={CLOCK_CHECK_INTERVAL_SECONDS} "
        f"bounded_export_max_bytes={MAX_BOUNDED_EXPORT_BYTES}"
    )
    maintenance.start(gateway_path, log)
    _start_health_monitor()
    _start_nvr_clock_monitor()
    _start_worker_watchdog()
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
