from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
from datetime import datetime, timezone

TASK_NAME_DEFAULT = "ZHIROX Hikvision Gateway"
APP_DIR = pathlib.Path(os.environ.get("LOCALAPPDATA", pathlib.Path.home())) / "ZHIROX" / "HikvisionGateway"
LOG_PATH = APP_DIR / "updater.log"
STATE_PATH = APP_DIR / "last_update.json"


def log(message: str) -> None:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).isoformat()
    with LOG_PATH.open("a", encoding="utf-8") as fh:
        fh.write(f"{stamp} {message}\n")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_file(path: pathlib.Path, expected_sha256: str) -> None:
    if not path.exists() or path.stat().st_size < 100_000:
        raise RuntimeError(f"update_file_invalid:{path.name}")
    if sha256_file(path).lower() != expected_sha256.lower():
        raise RuntimeError(f"update_file_sha256_mismatch:{path.name}")


def wait_for_parent(pid: int, timeout_seconds: int = 90) -> None:
    if os.name != "nt" or pid <= 0:
        return

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel32.WaitForSingleObject.restype = wintypes.DWORD
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL

    SYNCHRONIZE = 0x00100000
    WAIT_OBJECT_0 = 0x00000000
    handle = kernel32.OpenProcess(SYNCHRONIZE, False, pid)
    if not handle:
        # The parent may already have exited between handoff and OpenProcess.
        return
    try:
        result = kernel32.WaitForSingleObject(handle, timeout_seconds * 1000)
        if result != WAIT_OBJECT_0:
            raise RuntimeError("gateway_exit_timeout")
    finally:
        kernel32.CloseHandle(handle)


def run_schtasks(*args: str) -> subprocess.CompletedProcess:
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
    return subprocess.run(
        ["schtasks", *args],
        capture_output=True,
        text=True,
        timeout=30,
        creationflags=flags,
    )


def start_gateway_task(task_name: str) -> None:
    result = run_schtasks("/Run", "/TN", task_name)
    if result.returncode != 0:
        text = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(f"scheduled_task_start_failed:{text[:240]}")


def write_state(payload: dict) -> None:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    temp = STATE_PATH.with_suffix(".json.tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True), encoding="utf-8")
    os.replace(temp, STATE_PATH)


def replace_file(source: pathlib.Path, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + ".incoming")
    temp.unlink(missing_ok=True)
    shutil.copy2(source, temp)
    os.replace(temp, destination)


def apply_update(args: argparse.Namespace) -> int:
    current = pathlib.Path(args.current).resolve()
    new_gateway = pathlib.Path(args.new).resolve()
    installed_updater = pathlib.Path(args.installed_updater).resolve()
    new_updater = pathlib.Path(args.new_updater).resolve()
    backup = current.with_suffix(current.suffix + ".bak")

    verify_file(new_gateway, args.sha256)
    verify_file(new_updater, args.updater_sha256)
    wait_for_parent(args.parent_pid)

    if not current.exists():
        raise RuntimeError("installed_gateway_missing")

    previous_sha = sha256_file(current)
    backup.unlink(missing_ok=True)
    os.replace(current, backup)
    replaced = False
    try:
        replace_file(new_gateway, current)
        verify_file(current, args.sha256)
        replaced = True

        # This updater runs from the staged update directory, so the installed
        # updater can be safely refreshed for future update protocol changes.
        replace_file(new_updater, installed_updater)
        verify_file(installed_updater, args.updater_sha256)

        start_gateway_task(args.task_name)
        write_state({
            "status": "installed",
            "from_version": args.from_version,
            "to_version": args.to_version,
            "installed_at": datetime.now(timezone.utc).isoformat(),
            "previous_sha256": previous_sha,
            "new_sha256": args.sha256.lower(),
            "backup_path": str(backup),
        })
        log(f"update_installed from={args.from_version} to={args.to_version}")
        return 0
    except Exception as exc:
        log(f"update_failed type={type(exc).__name__} reason={str(exc)[:240]}")
        try:
            if replaced and current.exists():
                failed = current.with_suffix(current.suffix + ".failed")
                failed.unlink(missing_ok=True)
                os.replace(current, failed)
            if backup.exists():
                os.replace(backup, current)
            start_gateway_task(args.task_name)
            write_state({
                "status": "rolled_back",
                "from_version": args.from_version,
                "to_version": args.to_version,
                "rolled_back_at": datetime.now(timezone.utc).isoformat(),
                "reason": f"{type(exc).__name__}:{str(exc)[:240]}",
            })
        except Exception as rollback_exc:
            log(
                "rollback_failed "
                f"type={type(rollback_exc).__name__} reason={str(rollback_exc)[:240]}"
            )
        raise


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="ZHIROX Hikvision Gateway updater")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--parent-pid", type=int, default=0)
    p.add_argument("--current")
    p.add_argument("--new")
    p.add_argument("--sha256")
    p.add_argument("--installed-updater")
    p.add_argument("--new-updater")
    p.add_argument("--updater-sha256")
    p.add_argument("--task-name", default=TASK_NAME_DEFAULT)
    p.add_argument("--from-version", default="unknown")
    p.add_argument("--to-version", default="unknown")
    return p


def main() -> int:
    args = parser().parse_args()
    if not args.apply:
        return 0
    required = [
        args.current,
        args.new,
        args.sha256,
        args.installed_updater,
        args.new_updater,
        args.updater_sha256,
    ]
    if not all(required):
        raise RuntimeError("missing_update_arguments")
    return apply_update(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"updater_error type={type(exc).__name__} reason={str(exc)[:240]}")
        raise SystemExit(1)
