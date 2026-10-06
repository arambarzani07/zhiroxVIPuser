from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import html
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

from autostart import (
    TASK_NAME as AUTOSTART_TASK_NAME,
    current_windows_user,
    install_resilient_task,
)

TASK_NAME_DEFAULT = "ZHIROX Hikvision Gateway"
RECOVERY_TASK_NAME = "ZHIROX Hikvision Update Recovery"
UPDATE_PROTOCOL = 1
APP_DIR = pathlib.Path(os.environ.get("LOCALAPPDATA", pathlib.Path.home())) / "ZHIROX" / "HikvisionGateway"
LOG_PATH = APP_DIR / "updater.log"
STATE_PATH = APP_DIR / "last_update.json"
HEALTH_PATH = APP_DIR / "gateway-health.json"
LOCK_PATH = APP_DIR / "update.lock"
JOURNAL_PATH = APP_DIR / "update-transaction.json"

_WINDOWS_RESERVED = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


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


def verify_file(path: pathlib.Path, expected_sha256: str, min_size: int = 1) -> None:
    if not path.exists() or path.stat().st_size < min_size:
        raise RuntimeError(f"update_file_invalid:{path.name}")
    if sha256_file(path).lower() != expected_sha256.lower():
        raise RuntimeError(f"update_file_sha256_mismatch:{path.name}")


def _safe_relative_target(value: str) -> str:
    target = value.strip()
    if not target or len(target) > 240 or "\\" in target or ":" in target:
        raise RuntimeError("update_plan_target_invalid")
    parts = target.split("/")
    if any(not part or part in {".", ".."} for part in parts):
        raise RuntimeError("update_plan_target_invalid")
    for part in parts:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", part):
            raise RuntimeError("update_plan_target_invalid")
        if part.split(".", 1)[0].upper() in _WINDOWS_RESERVED:
            raise RuntimeError("update_plan_target_invalid")
    return "/".join(parts)


def _safe_target_path(install_dir: pathlib.Path, value: str) -> pathlib.Path:
    relative = _safe_relative_target(value)
    root = install_dir.resolve()
    target = (root / pathlib.PurePosixPath(relative)).resolve()
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise RuntimeError("update_plan_target_outside_install") from exc
    return target


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
        if error == 87:
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


def _end_gateway_task(task_name: str) -> None:
    try:
        run_schtasks("/End", "/TN", task_name)
    except Exception:
        pass


def start_gateway_task(task_name: str, gateway_path: pathlib.Path) -> None:
    ok, text = _try_start_task(task_name)
    if ok:
        return

    if task_name != AUTOSTART_TASK_NAME:
        raise RuntimeError(f"scheduled_task_start_failed:{text[:240]}")
    install_resilient_task(gateway_path)
    ok, text = _try_start_task(task_name)
    if not ok:
        raise RuntimeError(f"scheduled_task_start_failed:{text[:240]}")


def _recovery_task_xml(
    updater_exe: pathlib.Path,
    plan_path: pathlib.Path,
    install_dir: pathlib.Path,
    user_id: str,
) -> str:
    command = html.escape(str(updater_exe.resolve()))
    arguments = html.escape(
        f'--recover-plan "{plan_path.resolve()}" --install-dir "{install_dir.resolve()}"'
    )
    user = html.escape(user_id)
    return f'''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>ZHIROX Hikvision update power-loss recovery</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>{user}</UserId>
      <Delay>PT2S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{user}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{command}</Command>
      <Arguments>{arguments}</Arguments>
    </Exec>
  </Actions>
</Task>
'''


def install_recovery_task(
    updater_exe: pathlib.Path,
    plan_path: pathlib.Path,
    install_dir: pathlib.Path,
) -> None:
    if os.name != "nt":
        return
    xml = _recovery_task_xml(
        updater_exe,
        plan_path,
        install_dir,
        current_windows_user(),
    )
    temp_path: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".xml", encoding="utf-16", delete=False
        ) as fh:
            fh.write(xml)
            temp_path = pathlib.Path(fh.name)
        result = run_schtasks(
            "/Create", "/F", "/TN", RECOVERY_TASK_NAME, "/XML", str(temp_path)
        )
        if result.returncode != 0:
            raise RuntimeError(
                (result.stderr or result.stdout).strip() or "update_recovery_task_failed"
            )
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def delete_recovery_task() -> None:
    if os.name != "nt":
        return
    try:
        run_schtasks("/Delete", "/F", "/TN", RECOVERY_TASK_NAME)
    except Exception:
        pass


def _atomic_json_write(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True), encoding="utf-8")
    os.replace(temp, path)


def write_state(payload: dict) -> None:
    _atomic_json_write(STATE_PATH, payload)


def write_journal(payload: dict) -> None:
    _atomic_json_write(JOURNAL_PATH, payload)


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


def atomic_install(
    source: pathlib.Path,
    target: pathlib.Path,
    expected_sha256: str,
    min_size: int = 1,
) -> dict:
    target.parent.mkdir(parents=True, exist_ok=True)
    incoming = target.with_name(target.name + ".incoming")
    backup = target.with_name(target.name + ".bak")
    incoming.unlink(missing_ok=True)
    shutil.copy2(source, incoming)
    verify_file(incoming, expected_sha256, min_size=min_size)

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

    verify_file(target, expected_sha256, min_size=min_size)
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
    if not isinstance(assets, list) or not (2 <= len(assets) <= 64):
        raise RuntimeError("update_plan_assets_invalid")

    task_name = str(payload.get("task_name") or TASK_NAME_DEFAULT)
    if task_name != TASK_NAME_DEFAULT:
        raise RuntimeError("update_plan_task_name_invalid")

    release_commit = str(payload.get("release_commit") or "").lower()
    if not re.fullmatch(r"[0-9a-f]{40}", release_commit):
        raise RuntimeError("update_plan_release_commit_invalid")

    stage_dir = plan_path.parent.resolve()
    install_root = install_dir.resolve()
    clean_assets: list[dict] = []
    targets: set[str] = set()
    roles: set[str] = set()
    for item in assets:
        if not isinstance(item, dict):
            raise RuntimeError("update_plan_asset_invalid")
        target_name = _safe_relative_target(str(item.get("target") or ""))
        target_key = target_name.casefold()
        if target_key in targets:
            raise RuntimeError("update_plan_duplicate_target")
        targets.add(target_key)
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
        min_size = 100_000 if role in {"gateway", "updater"} else 1
        verify_file(source, digest, min_size=min_size)
        target = _safe_target_path(install_root, target_name)
        clean_assets.append({
            "name": str(item.get("name") or source.name),
            "source": source,
            "target": target,
            "target_name": target_name,
            "role": role,
            "sha256": digest,
            "min_size": min_size,
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
        "release_commit": release_commit,
        "task_name": task_name,
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
                return
        time.sleep(2)
    raise RuntimeError("post_update_health_timeout")


def _record_payload(record: dict, install_dir: pathlib.Path) -> dict:
    return {
        "target": record["target"].resolve().relative_to(install_dir.resolve()).as_posix(),
        "existed": bool(record["existed"]),
        "sha256": str(record["sha256"]).lower(),
    }


def _record_from_payload(payload: dict, install_dir: pathlib.Path) -> dict:
    target_name = _safe_relative_target(str(payload.get("target") or ""))
    target = _safe_target_path(install_dir, target_name)
    digest = str(payload.get("sha256") or "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise RuntimeError("update_journal_sha256_invalid")
    return {
        "target": target,
        "backup": target.with_name(target.name + ".bak"),
        "existed": bool(payload.get("existed")),
        "sha256": digest,
    }


def _journal_records(journal: dict, install_dir: pathlib.Path) -> list[dict]:
    records: list[dict] = []
    seen: set[str] = set()
    for raw in journal.get("records") or []:
        if not isinstance(raw, dict):
            continue
        record = _record_from_payload(raw, install_dir)
        key = str(record["target"]).casefold()
        if key not in seen:
            records.append(record)
            seen.add(key)

    current = journal.get("current_asset")
    if isinstance(current, dict):
        record = _record_from_payload(current, install_dir)
        target = record["target"]
        backup = record["backup"]
        installed = False
        try:
            installed = target.exists() and sha256_file(target).lower() == record["sha256"]
        except OSError:
            pass
        if installed or backup.exists():
            key = str(target).casefold()
            if key not in seen:
                records.append(record)
    return records


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


def _all_assets_installed(plan: dict) -> bool:
    for item in plan["assets"]:
        try:
            verify_file(item["target"], item["sha256"], min_size=item["min_size"])
        except Exception:
            return False
    return True


def _cleanup_recovery() -> None:
    delete_recovery_task()
    JOURNAL_PATH.unlink(missing_ok=True)
    LOCK_PATH.unlink(missing_ok=True)


def _initial_journal(plan_path: pathlib.Path, install_dir: pathlib.Path, plan: dict) -> dict:
    return {
        "schema": 1,
        "status": "installing",
        "plan_path": str(plan_path.resolve()),
        "install_dir": str(install_dir.resolve()),
        "from_version": plan["from_version"],
        "to_version": plan["to_version"],
        "release_commit": plan["release_commit"],
        "task_name": plan["task_name"],
        "gateway_target": plan["gateway"]["target_name"],
        "records": [],
        "current_asset": None,
        "started_at": datetime.now(timezone.utc).isoformat(),
    }


def apply_plan(plan_path: pathlib.Path, install_dir: pathlib.Path, parent_pid: int) -> int:
    plan_path = plan_path.resolve()
    install_dir = install_dir.resolve()
    plan = _load_plan(plan_path, install_dir)
    gateway_path: pathlib.Path = plan["gateway"]["target"]

    wait_for_parent(parent_pid)
    HEALTH_PATH.unlink(missing_ok=True)

    journal = _initial_journal(plan_path, install_dir, plan)
    write_journal(journal)
    updater_exe = pathlib.Path(sys.executable).resolve() if getattr(sys, "frozen", False) else pathlib.Path(__file__).resolve()
    install_recovery_task(updater_exe, plan_path, install_dir)

    ordered = sorted(plan["assets"], key=lambda item: item["role"] == "gateway")
    try:
        for item in ordered:
            intent = {
                "target": item["target_name"],
                "existed": item["target"].exists(),
                "sha256": item["sha256"],
            }
            journal["current_asset"] = intent
            write_journal(journal)
            record = atomic_install(
                item["source"],
                item["target"],
                item["sha256"],
                min_size=item["min_size"],
            )
            journal["records"].append(_record_payload(record, install_dir))
            journal["current_asset"] = None
            write_journal(journal)

        journal["status"] = "files_installed"
        write_journal(journal)
        start_gateway_task(plan["task_name"], gateway_path)
        wait_for_healthy_gateway(plan["to_version"], plan["health_timeout_seconds"])

        journal["status"] = "committed"
        journal["committed_at"] = datetime.now(timezone.utc).isoformat()
        write_journal(journal)
        write_state({
            "status": "installed",
            "from_version": plan["from_version"],
            "to_version": plan["to_version"],
            "release_commit": plan["release_commit"],
            "installed_at": datetime.now(timezone.utc).isoformat(),
            "assets": journal["records"],
            "post_update_health_verified": True,
            "power_recovery_armed": True,
        })
        log(
            f"update_installed from={plan['from_version']} to={plan['to_version']} "
            f"commit={plan['release_commit'][:12]} assets={len(journal['records'])} health=verified"
        )
        _cleanup_recovery()
        return 0
    except Exception as exc:
        log(f"update_failed type={type(exc).__name__} reason={str(exc)[:240]}")
        try:
            _end_gateway_task(plan["task_name"])
            rollback_assets(_journal_records(journal, install_dir))
            HEALTH_PATH.unlink(missing_ok=True)
            if gateway_path.exists():
                start_gateway_task(plan["task_name"], gateway_path)
            write_state({
                "status": "rolled_back",
                "from_version": plan["from_version"],
                "to_version": plan["to_version"],
                "release_commit": plan["release_commit"],
                "rolled_back_at": datetime.now(timezone.utc).isoformat(),
                "reason": f"{type(exc).__name__}:{str(exc)[:240]}",
            })
            _cleanup_recovery()
        except Exception as rollback_exc:
            log(
                "rollback_failed "
                f"type={type(rollback_exc).__name__} reason={str(rollback_exc)[:240]}"
            )
            # Keep the journal, lock and recovery task. The next Windows logon
            # gets another independent chance to restore the known-good files.
        raise


def recover_pending(plan_path: pathlib.Path, install_dir: pathlib.Path) -> int:
    install_dir = install_dir.resolve()
    if not JOURNAL_PATH.exists():
        delete_recovery_task()
        LOCK_PATH.unlink(missing_ok=True)
        return 0

    try:
        journal = json.loads(JOURNAL_PATH.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError("update_recovery_journal_invalid") from exc
    if int(journal.get("schema") or 0) != 1:
        raise RuntimeError("update_recovery_journal_schema_invalid")
    if pathlib.Path(str(journal.get("install_dir") or "")).resolve() != install_dir:
        raise RuntimeError("update_recovery_install_dir_mismatch")

    task_name = str(journal.get("task_name") or TASK_NAME_DEFAULT)
    if task_name != TASK_NAME_DEFAULT:
        raise RuntimeError("update_recovery_task_name_invalid")
    gateway_path = _safe_target_path(install_dir, str(journal.get("gateway_target") or ""))

    _end_gateway_task(task_name)

    if journal.get("status") == "committed":
        if gateway_path.exists():
            start_gateway_task(task_name, gateway_path)
        _cleanup_recovery()
        return 0

    plan: dict | None = None
    try:
        plan = _load_plan(plan_path.resolve(), install_dir)
    except Exception as exc:
        log(f"recovery_plan_unavailable={type(exc).__name__}:{str(exc)[:180]}")

    if plan is not None and _all_assets_installed(plan):
        HEALTH_PATH.unlink(missing_ok=True)
        try:
            start_gateway_task(task_name, gateway_path)
            wait_for_healthy_gateway(plan["to_version"], plan["health_timeout_seconds"])
            write_state({
                "status": "installed",
                "from_version": plan["from_version"],
                "to_version": plan["to_version"],
                "release_commit": plan["release_commit"],
                "installed_at": datetime.now(timezone.utc).isoformat(),
                "post_update_health_verified": True,
                "recovered_after_power_loss": True,
            })
            log(f"power_recovery_committed to={plan['to_version']}")
            _cleanup_recovery()
            return 0
        except Exception as exc:
            log(f"power_recovery_health_failed={type(exc).__name__}:{str(exc)[:180]}")
            _end_gateway_task(task_name)

    records = _journal_records(journal, install_dir)
    rollback_assets(records)
    HEALTH_PATH.unlink(missing_ok=True)
    if gateway_path.exists():
        start_gateway_task(task_name, gateway_path)
    write_state({
        "status": "rolled_back",
        "from_version": str(journal.get("from_version") or "unknown"),
        "to_version": str(journal.get("to_version") or "unknown"),
        "release_commit": str(journal.get("release_commit") or "unknown"),
        "rolled_back_at": datetime.now(timezone.utc).isoformat(),
        "reason": "power_interrupted_update_recovered",
        "recovered_after_power_loss": True,
    })
    log(f"power_recovery_rolled_back records={len(records)}")
    _cleanup_recovery()
    return 0


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="ZHIROX Hikvision Gateway evergreen updater")
    p.add_argument("--apply-plan")
    p.add_argument("--recover-plan")
    p.add_argument("--parent-pid", type=int, default=0)
    p.add_argument("--install-dir")
    return p


def main() -> int:
    args = parser().parse_args()
    if not args.apply_plan and not args.recover_plan:
        return 0
    if not args.install_dir:
        raise RuntimeError("missing_install_dir")
    if args.apply_plan and args.recover_plan:
        raise RuntimeError("conflicting_update_modes")
    if args.recover_plan:
        return recover_pending(pathlib.Path(args.recover_plan), pathlib.Path(args.install_dir))
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
        raise SystemExit(1)
