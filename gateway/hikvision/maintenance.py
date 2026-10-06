from __future__ import annotations

import pathlib
import shutil
import threading
import time
from typing import Callable

from common import APP_DIR, LOG_PATH, TEMP_DIR

UPDATER_LOG_PATH = APP_DIR / "updater.log"
UPDATE_ROOT = APP_DIR / "updates"
UPDATE_LOCK_PATH = APP_DIR / "update.lock"
UPDATE_JOURNAL_PATH = APP_DIR / "update-transaction.json"

MAINTENANCE_INTERVAL_SECONDS = 60 * 60
GATEWAY_LOG_MAX_BYTES = 5 * 1024 * 1024
UPDATER_LOG_MAX_BYTES = 2 * 1024 * 1024
TEMP_MAX_AGE_SECONDS = 24 * 60 * 60
ORPHAN_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
STAGE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60


def update_in_progress() -> bool:
    return UPDATE_LOCK_PATH.exists() or UPDATE_JOURNAL_PATH.exists()


def _age_seconds(path: pathlib.Path, now: float | None = None) -> float:
    now = time.time() if now is None else now
    return max(0.0, now - path.stat().st_mtime)


def rotate_file(path: pathlib.Path, max_bytes: int, backups: int = 2) -> None:
    if max_bytes <= 0 or backups < 1:
        return
    try:
        if not path.exists() or path.stat().st_size <= max_bytes:
            return
    except OSError:
        return

    try:
        oldest = path.with_name(f"{path.name}.{backups}")
        oldest.unlink(missing_ok=True)
        for index in range(backups - 1, 0, -1):
            src = path.with_name(f"{path.name}.{index}")
            dst = path.with_name(f"{path.name}.{index + 1}")
            if src.exists():
                src.replace(dst)
        path.replace(path.with_name(f"{path.name}.1"))
    except OSError:
        # Maintenance is best-effort; never interrupt evidence capture.
        return


def cleanup_stale_temp(now: float | None = None) -> int:
    now = time.time() if now is None else now
    removed = 0
    if not TEMP_DIR.exists():
        return removed
    for child in TEMP_DIR.iterdir():
        try:
            if child.is_file() and _age_seconds(child, now) > TEMP_MAX_AGE_SECONDS:
                child.unlink(missing_ok=True)
                removed += 1
        except OSError:
            continue
    return removed


def cleanup_orphan_install_files(
    install_dir: pathlib.Path,
    now: float | None = None,
) -> int:
    if update_in_progress():
        return 0
    now = time.time() if now is None else now
    removed = 0
    try:
        candidates = list(install_dir.rglob("*.incoming")) + list(install_dir.rglob("*.failed"))
    except OSError:
        return 0
    for child in candidates:
        try:
            if child.is_file() and _age_seconds(child, now) > ORPHAN_MAX_AGE_SECONDS:
                child.unlink(missing_ok=True)
                removed += 1
        except OSError:
            continue
    return removed


def cleanup_old_update_stages(now: float | None = None) -> int:
    if update_in_progress() or not UPDATE_ROOT.exists():
        return 0
    now = time.time() if now is None else now
    removed = 0
    for child in UPDATE_ROOT.iterdir():
        try:
            if child.is_dir() and _age_seconds(child, now) > STAGE_MAX_AGE_SECONDS:
                shutil.rmtree(child)
                removed += 1
        except OSError:
            continue
    return removed


def run_once(installed_gateway: pathlib.Path, log: Callable[[str], None]) -> None:
    rotate_file(LOG_PATH, GATEWAY_LOG_MAX_BYTES)
    if not update_in_progress():
        rotate_file(UPDATER_LOG_PATH, UPDATER_LOG_MAX_BYTES)

    temp_removed = cleanup_stale_temp()
    orphan_removed = cleanup_orphan_install_files(installed_gateway.parent)
    stages_removed = cleanup_old_update_stages()
    if temp_removed or orphan_removed or stages_removed:
        log(
            "maintenance_cleanup "
            f"temp={temp_removed} orphan={orphan_removed} stages={stages_removed}"
        )


def _loop(installed_gateway: pathlib.Path, log: Callable[[str], None]) -> None:
    while True:
        try:
            run_once(installed_gateway, log)
        except Exception as exc:
            log(f"maintenance_error={type(exc).__name__}:{str(exc)[:200]}")
        time.sleep(MAINTENANCE_INTERVAL_SECONDS)


def start(installed_gateway: pathlib.Path, log: Callable[[str], None]) -> None:
    try:
        run_once(installed_gateway, log)
    except Exception as exc:
        log(f"maintenance_start_error={type(exc).__name__}:{str(exc)[:200]}")
    threading.Thread(
        target=_loop,
        args=(installed_gateway, log),
        name="zhirox-gateway-maintenance",
        daemon=True,
    ).start()
