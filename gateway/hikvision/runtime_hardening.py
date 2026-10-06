from __future__ import annotations

import ctypes
import json
import os
import pathlib
import shutil
import threading
import time
from contextlib import contextmanager

from common import APP_DIR, CONFIG_PATH, LOG_PATH, TEMP_DIR, GatewayConfig

LOG_MAX_BYTES = 5 * 1024 * 1024
LOG_BACKUPS = 3
HOUSEKEEPING_SECONDS = 10 * 60
TEMP_MAX_AGE_SECONDS = 24 * 60 * 60
CONFIG_BACKUP_PATH = APP_DIR / "config.json.bak"
_MUTEX_NAME = "Local\\ZHIROX-Hikvision-Gateway"
_mutex_handle = None
_housekeeping_started = False


def acquire_single_instance() -> bool:
    """Return False when another Gateway process already owns the mutex."""
    global _mutex_handle
    if os.name != "nt":
        return True
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p]
    kernel32.CreateMutexW.restype = ctypes.c_void_p
    handle = kernel32.CreateMutexW(None, False, _MUTEX_NAME)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    ERROR_ALREADY_EXISTS = 183
    if ctypes.get_last_error() == ERROR_ALREADY_EXISTS:
        kernel32.CloseHandle(handle)
        return False
    _mutex_handle = handle
    return True


def _config_is_usable(path: pathlib.Path) -> bool:
    if not path.exists():
        return False
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        required = {"nvr_host", "nvr_password_dpapi", "gateway_token_dpapi"}
        if not required.issubset(payload):
            return False
        # DPAPI decryption is the real integrity check for the current user.
        original = CONFIG_PATH
        if path == original:
            GatewayConfig.load()
            return True
        current_bytes = original.read_bytes() if original.exists() else None
        try:
            original.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, original)
            GatewayConfig.load()
            return True
        finally:
            if current_bytes is None:
                original.unlink(missing_ok=True)
            else:
                temp = original.with_suffix(".restore.tmp")
                temp.write_bytes(current_bytes)
                os.replace(temp, original)
    except Exception:
        return False


def recover_or_backup_config(log) -> None:
    """Keep one known-good DPAPI config and restore it after corruption."""
    APP_DIR.mkdir(parents=True, exist_ok=True)
    if _config_is_usable(CONFIG_PATH):
        try:
            temp = CONFIG_BACKUP_PATH.with_suffix(".bak.tmp")
            shutil.copy2(CONFIG_PATH, temp)
            os.replace(temp, CONFIG_BACKUP_PATH)
        except OSError as exc:
            log(f"config_backup_error={type(exc).__name__}:{str(exc)[:180]}")
        return
    if _config_is_usable(CONFIG_BACKUP_PATH):
        temp = CONFIG_PATH.with_suffix(".recovery.tmp")
        shutil.copy2(CONFIG_BACKUP_PATH, temp)
        os.replace(temp, CONFIG_PATH)
        log("config_recovered_from_known_good_backup=true")


def cleanup_stale_temp(log, now: float | None = None) -> int:
    """Remove abandoned media/temp files left by old crashes, never fresh files."""
    if not TEMP_DIR.exists():
        return 0
    cutoff = (time.time() if now is None else now) - TEMP_MAX_AGE_SECONDS
    removed = 0
    for path in TEMP_DIR.iterdir():
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
                removed += 1
        except OSError:
            continue
    if removed:
        log(f"stale_temp_cleanup removed={removed}")
    return removed


def rotate_gateway_log_if_needed() -> bool:
    try:
        if not LOG_PATH.exists() or LOG_PATH.stat().st_size < LOG_MAX_BYTES:
            return False
        for index in range(LOG_BACKUPS, 0, -1):
            src = LOG_PATH.with_name(f"{LOG_PATH.name}.{index}")
            if index == LOG_BACKUPS:
                src.unlink(missing_ok=True)
            else:
                dst = LOG_PATH.with_name(f"{LOG_PATH.name}.{index + 1}")
                if src.exists():
                    os.replace(src, dst)
        os.replace(LOG_PATH, LOG_PATH.with_name(f"{LOG_PATH.name}.1"))
        return True
    except OSError:
        return False


def _housekeeping_loop(log) -> None:
    while True:
        time.sleep(HOUSEKEEPING_SECONDS)
        if rotate_gateway_log_if_needed():
            log("gateway_log_rotated=true")
        cleanup_stale_temp(log)


def start_housekeeping(log) -> None:
    global _housekeeping_started
    if _housekeeping_started:
        return
    _housekeeping_started = True
    rotate_gateway_log_if_needed()
    cleanup_stale_temp(log)
    threading.Thread(
        target=_housekeeping_loop,
        args=(log,),
        name="zhirox-gateway-housekeeping",
        daemon=True,
    ).start()


@contextmanager
def keep_system_awake():
    """Prevent Windows sleep only while a transaction video job is active."""
    if os.name != "nt":
        yield
        return
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    ES_CONTINUOUS = 0x80000000
    ES_SYSTEM_REQUIRED = 0x00000001
    kernel32.SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
    try:
        yield
    finally:
        kernel32.SetThreadExecutionState(ES_CONTINUOUS)


def wrap_process_job(agent_module, log) -> None:
    original = agent_module.process_job
    if getattr(original, "_zhirox_awake_wrapped", False):
        return

    def wrapped(*args, **kwargs):
        with keep_system_awake():
            return original(*args, **kwargs)

    wrapped._zhirox_awake_wrapped = True
    agent_module.process_job = wrapped
    log("active_job_sleep_guard=enabled")
