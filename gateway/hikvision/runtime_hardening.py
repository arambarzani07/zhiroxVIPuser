from __future__ import annotations

import ctypes
import json
import os
import pathlib
import shutil
from contextlib import contextmanager

from common import APP_DIR, CONFIG_PATH, GatewayConfig

CONFIG_BACKUP_PATH = APP_DIR / "config.json.bak"
_MUTEX_NAME = "Local\\ZHIROX-Hikvision-Gateway"
_mutex_handle = None


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
        if path == CONFIG_PATH:
            GatewayConfig.load()
            return True

        current_bytes = CONFIG_PATH.read_bytes() if CONFIG_PATH.exists() else None
        try:
            CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, CONFIG_PATH)
            GatewayConfig.load()
            return True
        finally:
            if current_bytes is None:
                CONFIG_PATH.unlink(missing_ok=True)
            else:
                temp = CONFIG_PATH.with_suffix(".restore.tmp")
                temp.write_bytes(current_bytes)
                os.replace(temp, CONFIG_PATH)
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
