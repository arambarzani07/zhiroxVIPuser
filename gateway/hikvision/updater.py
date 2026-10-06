from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import time
from datetime import datetime, timezone

from autostart import TASK_NAME as AUTOSTART_TASK_NAME, install_resilient_task

TASK_NAME_DEFAULT = "ZHIROX Hikvision Gateway"
UPDATE_PROTOCOL = 1
APP_DIR = pathlib.Path(os.environ.get("LOCALAPPDATA", pathlib.Path.home())) / "ZHIROX" / "HikvisionGateway"
LOG_PATH = APP_DIR / "updater.log"
STATE_PATH = APP_DIR / "last_update.json"
HEALTH_PATH = APP_DIR / "gateway-health.json"
LOCK_PATH = APP_DIR / "update.lock"


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


def _safe_target_name(value: str) -> str:
    name = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", name):
        raise RuntimeError("update_plan_target_invalid")
    if pathlib.Path(name).name != name or name in {".", ".."}:
        raise RuntimeError("update_plan_target_invalid")
    return name


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
        error = ctypes.get_last_error()
        if error == 87:  # ERROR_INVALID_PARAMETER: process already exited.
            return
        raise OSError(error, "OpenProcess failed while waiting for Gateway exit")
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


def _try_start_task(task_name: str, attempts: int = 6) -> tuple[bool, str]:
    last_text = ""
    for _ in range(attempts):
        result = run_schtasks("/Run", "/TN", task_name)
        if result.returncode == 0:
            return True, ""
        last_text = (result.stderr or result.stdout or "").strip()
        time.sleep(2)
    return False, last_text


def start_gateway_task(task_name: str, gateway_path: pathlib.Path) -> None:
    ok, text = _try_start_task(task_name)
    if ok:
        return

    # A deleted/corrupted task must not turn an automatic update into a manual
    # repair. Recreate the resilient task and try again.
    if task_name != AUTOSTART_TASK_NAME:
        raise RuntimeError(f"scheduled_task_start_failed:{text[:240]}")
    install_resilient_task(gateway_path)
    ok, text = _try_start_task(task_name)
    if not ok:
        raise RuntimeError(f"scheduled_task_start_failed:{text[:240]}")


def write_state(payload: dict) -> None:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    temp = STATE_PATH.with_suffix(".json.tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True), encoding="utf-8")
    os.replace(temp, STATE_PATH)


def _replace_file_windows(
    destination: pathlib.Path,
    replacement: pathlib.Path,
    backup: pathlib.Path,
) -> None:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.ReplaceFileW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.LPVOID,
        wintypes.LPVOID,
    ]
    kernel32.ReplaceFileW.restype = wintypes.BOOL
    REPLACEFILE_IGNORE_MERGE_ERRORS = 0x00000002
    ok = kernel32.ReplaceFileW(
        str(destination),
        str(replacement),
        str(backup),
        REPLACEFILE_IGNORE_MERGE_ERRORS,
        None,
        None,
    )
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())


def atomic_install(source: pathlib.Path, target: pathlib.Path, expected_sha256: str) -> dict:
    target.parent.mkdir(parents=True, exist_ok=True)
    incoming = target.with_name(target.name + ".incoming")
    backup = target.with_name(target.name + ".bak")
    incoming.unlink(missing_ok=True)
    shutil.copy2(source, incoming)
    verify_file(incoming, expected_sha256)

    existed = target.exists()
    if existed:
        backup.unlink(missing_ok=True)
        if os.name == "nt":
            _replace_file_windows(target, incoming, backup)
        else:
            os.replace(target, backup)
            os.replace(incoming, target)
    else:
        os.replace(incoming, target)

    verify_file(target, expected_sha256)
    return {
        "target": target,
        "backup": backup,
        "existed": existed,
        "sha256": expected_sha256.lower(),
    }


def _load_plan(plan_path: pathlib.Path, install_dir: pathlib.Path) -> dict:
    try:
        payload = json.loads(plan_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError("update_plan_json_invalid") from exc
    if int(payload.get("schema") or 0) != 1:
        raise RuntimeError("update_plan_schema_unsupported")
    if int(payload.get("protocol") or 0) > UPDATE_PROTOCOL:
        raise RuntimeError("update_plan_protocol_unsupported")

    assets = payload.get("assets")
    if not isinstance(assets, list) or not (2 <= len(assets) <= 16):
        raise RuntimeError("update_plan_assets_invalid")

    stage_dir = plan_path.parent.resolve()
    clean_assets: list[dict] = []
    targets: set[str] = set()
    roles: set[str] = set()
    for item in assets:
        if not isinstance(item, dict):
            raise RuntimeError("update_plan_asset_invalid")
        target_name = _safe_target_name(str(item.get("target") or ""))
        if target_name in targets:
            raise RuntimeError("update_plan_duplicate_target")
        targets.add(target_name)
        role = str(item.get("role") or "companion").strip().lower()
        if role not in {"gateway", "updater", "companion"}:
            raise RuntimeError("update_plan_role_invalid")
        if role in {"gateway", "updater"} and role in roles:
            raise RuntimeError("update_plan_duplicate_role")
        roles.add(role)
        source = pathlib.Path(str(item.get("source") or "")).resolve()
        if source.parent != stage_dir:
            raise RuntimeError("update_plan_source_outside_stage")
        digest = str(item.get("sha256") or "").lower()
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise RuntimeError("update_plan_sha256_invalid")
        verify_file(source, digest)
        clean_assets.append({
            "name": str(item.get("name") or source.name),
            "source": source,
            "target": (install_dir / target_name).resolve(),
            "target_name": target_name,
            "role": role,
            "sha256": digest,
        })

    if "gateway" not in roles or "updater" not in roles:
        raise RuntimeError("update_plan_core_assets_missing")

    gateway = next(item for item in clean_assets if item["role"] == "gateway")
    updater = next(item for item in clean_assets if item["role"] == "updater")
    timeout = int(payload.get("health_timeout_seconds") or 90)
    timeout = min(300, max(45, timeout))
    return {
        "from_version": str(payload.get("from_version") or "unknown"),
        "to_version": str(payload.get("to_version") or "unknown"),
        "task_name": str(payload.get("task_name") or TASK_NAME_DEFAULT),
        "health_timeout_seconds": timeout,
        "assets": clean_assets,
        "gateway": gateway,
        "updater": updater,
    }


def _read_health(expected_version: str) -> tuple[bool, float]:
    try:
        stat = HEALTH_PATH.stat()
        payload = json.loads(HEALTH_PATH.read_text(encoding="utf-8"))
        if (
            payload.get("status") == "healthy"
            and str(payload.get("version") or "") == expected_version
        ):
            return True, stat.st_mtime
    except Exception:
        pass
    return False, 0.0


def wait_for_healthy_gateway(expected_version: str, timeout_seconds: int) -> None:
    deadline = time.monotonic() + timeout_seconds
    first_mtime = 0.0
    while time.monotonic() < deadline:
        healthy, mtime = _read_health(expected_version)
        if healthy:
            if first_mtime == 0.0:
                first_mtime = mtime
            elif mtime > first_mtime:
                # A second heartbeat proves the new process stayed alive after
                # bootstrap instead of only writing one startup marker.
                return
        time.sleep(2)
    raise RuntimeError("post_update_health_timeout")


def rollback_assets(records: list[dict]) -> None:
    for record in reversed(records):
        target: pathlib.Path = record["target"]
        backup: pathlib.Path = record["backup"]
        if backup.exists():
            if target.exists():
                failed = target.with_name(target.name + ".failed")
                failed.unlink(missing_ok=True)
                os.replace(target, failed)
            os.replace(backup, target)
        elif not record["existed"]:
            target.unlink(missing_ok=True)


def apply_plan(plan_path: pathlib.Path, install_dir: pathlib.Path, parent_pid: int) -> int:
    plan = _load_plan(plan_path.resolve(), install_dir.resolve())
    gateway_path: pathlib.Path = plan["gateway"]["target"]
    records: list[dict] = []

    wait_for_parent(parent_pid)
    HEALTH_PATH.unlink(missing_ok=True)

    # Install companions/updater first and Gateway last. If power disappears in
    # the middle, the old Gateway remains executable until all dependencies are
    # already in place. ReplaceFileW makes each existing-file swap atomic.
    ordered = sorted(plan["assets"], key=lambda item: item["role"] == "gateway")
    try:
        for item in ordered:
            records.append(atomic_install(item["source"], item["target"], item["sha256"]))

        start_gateway_task(plan["task_name"], gateway_path)
        wait_for_healthy_gateway(plan["to_version"], plan["health_timeout_seconds"])

        write_state({
            "status": "installed",
            "from_version": plan["from_version"],
            "to_version": plan["to_version"],
            "installed_at": datetime.now(timezone.utc).isoformat(),
            "assets": [
                {
                    "target": record["target"].name,
                    "sha256": record["sha256"],
                    "backup": str(record["backup"]) if record["backup"].exists() else None,
                }
                for record in records
            ],
            "post_update_health_verified": True,
        })
        log(
            f"update_installed from={plan['from_version']} to={plan['to_version']} "
            f"assets={len(records)} health=verified"
        )
        return 0
    except Exception as exc:
        log(f"update_failed type={type(exc).__name__} reason={str(exc)[:240]}")
        try:
            rollback_assets(records)
            HEALTH_PATH.unlink(missing_ok=True)
            if gateway_path.exists():
                start_gateway_task(plan["task_name"], gateway_path)
            write_state({
                "status": "rolled_back",
                "from_version": plan["from_version"],
                "to_version": plan["to_version"],
                "rolled_back_at": datetime.now(timezone.utc).isoformat(),
                "reason": f"{type(exc).__name__}:{str(exc)[:240]}",
            })
        except Exception as rollback_exc:
            log(
                "rollback_failed "
                f"type={type(rollback_exc).__name__} reason={str(rollback_exc)[:240]}"
            )
        raise
    finally:
        try:
            LOCK_PATH.unlink(missing_ok=True)
        except OSError:
            pass


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="ZHIROX Hikvision Gateway evergreen updater")
    p.add_argument("--apply-plan")
    p.add_argument("--parent-pid", type=int, default=0)
    p.add_argument("--install-dir")
    return p


def main() -> int:
    args = parser().parse_args()
    if not args.apply_plan:
        return 0
    if not args.install_dir:
        raise RuntimeError("missing_install_dir")
    return apply_plan(
        pathlib.Path(args.apply_plan),
        pathlib.Path(args.install_dir),
        args.parent_pid,
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"updater_error type={type(exc).__name__} reason={str(exc)[:240]}")
        try:
            LOCK_PATH.unlink(missing_ok=True)
        except OSError:
            pass
        raise SystemExit(1)
