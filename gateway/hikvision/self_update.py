from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
from typing import Callable
from urllib.parse import urlsplit

import requests

REPOSITORY = "arambarzani07/zhiroxVIPuser"
RELEASES_URL = f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=30"
TAG_PREFIX = "hikvision-gateway-v"
MANIFEST_ASSET = "gateway-update.json"
GATEWAY_ASSET = "zhirox-hikvision-gateway.exe"
UPDATER_ASSET = "zhirox-hikvision-updater.exe"
UPDATE_PROTOCOL = 1
CHECK_INTERVAL_SECONDS = 30 * 60
TASK_NAME = "ZHIROX Hikvision Gateway"
LOCK_STALE_SECONDS = 30 * 60
MIN_FREE_RESERVE_BYTES = 128 * 1024 * 1024
MAX_RELEASE_ASSETS = 16

_HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2026-03-10",
    "User-Agent": "ZHIROX-Hikvision-Gateway",
}


def version_key(value: str) -> tuple[int, int, int, int]:
    """Compare product versions, including a trailing numeric build revision.

    Examples:
      1.4.0+evergreen-2 > 1.4.0+evergreen-1
      1.4.1 > 1.4.0+evergreen-999

    Future releases should either bump x.y.z or the final numeric build revision.
    """
    match = re.search(r"(?:^|v)(\d+)\.(\d+)\.(\d+)", value)
    if not match:
        raise ValueError("invalid_gateway_version")
    major, minor, patch = (int(part) for part in match.groups())
    build = 0
    if "+" in value:
        metadata = value.split("+", 1)[1]
        revision = re.search(r"(?:^|[-_.])(\d+)$", metadata)
        if revision:
            build = int(revision.group(1))
    return major, minor, patch, build


def version_tuple(value: str) -> tuple[int, int, int]:
    # Kept for compatibility with older tests/helpers.
    return version_key(value)[:3]


def _release_version(release: dict) -> str | None:
    tag = str(release.get("tag_name") or "")
    if not tag.startswith(TAG_PREFIX):
        return None
    return tag[len(TAG_PREFIX):]


def _release_has_asset(release: dict, name: str) -> bool:
    return any(asset.get("name") == name for asset in (release.get("assets") or []))


def _get_with_retry(session, url: str, *, attempts: int = 3, **kwargs):
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            response = session.get(url, **kwargs)
            response.raise_for_status()
            return response
        except Exception as exc:
            last_error = exc
            if attempt + 1 >= attempts:
                raise
            time.sleep(2 ** attempt)
    assert last_error is not None
    raise last_error


def find_newer_release(current_version: str, session=requests) -> dict | None:
    response = _get_with_retry(
        session,
        RELEASES_URL,
        headers=_HEADERS,
        timeout=(8, 20),
    )
    current = version_key(current_version)
    candidates: list[tuple[tuple[int, int, int, int], dict]] = []
    for release in response.json():
        if release.get("draft") or release.get("prerelease"):
            continue
        version = _release_version(release)
        if not version or not _release_has_asset(release, MANIFEST_ASSET):
            continue
        parsed = version_key(version)
        if parsed > current:
            item = dict(release)
            item["_gateway_version"] = version
            candidates.append((parsed, item))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def _asset(release: dict, name: str, *, min_size: int = 1) -> dict:
    for asset in release.get("assets") or []:
        if asset.get("name") == name:
            digest = str(asset.get("digest") or "")
            if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
                raise RuntimeError(f"update_asset_digest_missing:{name}")
            if int(asset.get("size") or 0) < min_size:
                raise RuntimeError(f"update_asset_too_small:{name}")
            url = str(asset.get("browser_download_url") or "")
            parsed = urlsplit(url)
            if parsed.scheme != "https" or parsed.netloc.lower() != "github.com":
                raise RuntimeError(f"update_asset_url_rejected:{name}")
            prefix = f"/{REPOSITORY}/releases/download/"
            if not parsed.path.startswith(prefix):
                raise RuntimeError(f"update_asset_repo_mismatch:{name}")
            return asset
    raise RuntimeError(f"update_asset_missing:{name}")


def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_verified(asset: dict, destination: pathlib.Path, session=requests) -> str:
    expected = str(asset["digest"]).split(":", 1)[1].lower()
    expected_size = int(asset["size"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + ".part")
    last_error: Exception | None = None

    for attempt in range(3):
        temp.unlink(missing_ok=True)
        try:
            with session.get(
                str(asset["browser_download_url"]),
                headers=_HEADERS,
                timeout=(10, 180),
                stream=True,
                allow_redirects=True,
            ) as response:
                response.raise_for_status()
                host = urlsplit(response.url).netloc.lower()
                if host != "github.com" and not host.endswith(".githubusercontent.com"):
                    raise RuntimeError("update_download_redirect_rejected")
                with temp.open("wb") as fh:
                    for chunk in response.iter_content(chunk_size=1024 * 1024):
                        if chunk:
                            fh.write(chunk)
            if not temp.exists() or temp.stat().st_size != expected_size:
                raise RuntimeError("update_asset_size_mismatch")
            actual = _sha256(temp)
            if actual != expected:
                raise RuntimeError("update_asset_sha256_mismatch")
            os.replace(temp, destination)
            return expected
        except Exception as exc:
            last_error = exc
            temp.unlink(missing_ok=True)
            if attempt + 1 >= 3:
                raise
            time.sleep(2 ** attempt)

    assert last_error is not None
    raise last_error


def _safe_target_name(value: str) -> str:
    name = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", name):
        raise RuntimeError("update_manifest_target_invalid")
    if pathlib.Path(name).name != name or name in {".", ".."}:
        raise RuntimeError("update_manifest_target_invalid")
    return name


def validate_manifest(payload: dict, expected_version: str) -> list[dict]:
    if int(payload.get("schema") or 0) != 1:
        raise RuntimeError("update_manifest_schema_unsupported")
    if int(payload.get("protocol") or 0) > UPDATE_PROTOCOL:
        raise RuntimeError("update_protocol_upgrade_required")
    if str(payload.get("version") or "") != expected_version:
        raise RuntimeError("update_manifest_version_mismatch")

    raw_assets = payload.get("assets")
    if not isinstance(raw_assets, list) or not (2 <= len(raw_assets) <= MAX_RELEASE_ASSETS):
        raise RuntimeError("update_manifest_assets_invalid")

    assets: list[dict] = []
    names: set[str] = set()
    targets: set[str] = set()
    roles: set[str] = set()
    for item in raw_assets:
        if not isinstance(item, dict):
            raise RuntimeError("update_manifest_asset_invalid")
        name = _safe_target_name(str(item.get("name") or ""))
        target = _safe_target_name(str(item.get("target") or ""))
        role = str(item.get("role") or "companion").strip().lower()
        if role not in {"gateway", "updater", "companion"}:
            raise RuntimeError("update_manifest_role_invalid")
        if name in names or target in targets:
            raise RuntimeError("update_manifest_duplicate_asset")
        if role in {"gateway", "updater"} and role in roles:
            raise RuntimeError("update_manifest_duplicate_role")
        names.add(name)
        targets.add(target)
        roles.add(role)
        assets.append({"name": name, "target": target, "role": role})

    if "gateway" not in roles or "updater" not in roles:
        raise RuntimeError("update_manifest_core_assets_missing")
    return assets


def _hidden_flags() -> int:
    if os.name != "nt":
        return 0
    return getattr(subprocess, "CREATE_NO_WINDOW", 0)


def _detached_flags() -> int:
    if os.name != "nt":
        return 0
    return (
        getattr(subprocess, "DETACHED_PROCESS", 0)
        | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    )


def cleanup_old_updates(update_root: pathlib.Path, keep: pathlib.Path | None = None) -> None:
    if not update_root.exists():
        return
    for child in update_root.iterdir():
        if keep is not None and child.resolve() == keep.resolve():
            continue
        if child.is_dir():
            try:
                shutil.rmtree(child)
            except OSError:
                pass


def _acquire_update_lock(app_dir: pathlib.Path) -> pathlib.Path | None:
    app_dir.mkdir(parents=True, exist_ok=True)
    lock = app_dir / "update.lock"
    if lock.exists():
        try:
            age = time.time() - lock.stat().st_mtime
            if age < LOCK_STALE_SECONDS:
                return None
            lock.unlink(missing_ok=True)
        except OSError:
            return None
    try:
        fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        return None
    try:
        os.write(fd, f"pid={os.getpid()}\ncreated={time.time()}\n".encode("ascii"))
    finally:
        os.close(fd)
    return lock


def _ensure_disk_space(path: pathlib.Path, total_download_bytes: int) -> None:
    free = shutil.disk_usage(path).free
    required = (total_download_bytes * 2) + MIN_FREE_RESERVE_BYTES
    if free < required:
        raise RuntimeError("update_insufficient_disk_space")


def maybe_auto_update(
    current_version: str,
    installed_gateway: pathlib.Path,
    app_dir: pathlib.Path,
    log: Callable[[str], None],
    session=requests,
) -> bool:
    if os.name != "nt" or not getattr(sys, "frozen", False):
        return False
    if os.environ.get("ZHIROX_DISABLE_AUTO_UPDATE", "").strip() == "1":
        return False

    release = find_newer_release(current_version, session=session)
    if release is None:
        return False

    lock = _acquire_update_lock(app_dir)
    if lock is None:
        return False
    handed_off = False
    try:
        new_version = str(release["_gateway_version"])
        safe_version = re.sub(r"[^0-9A-Za-z._+-]", "_", new_version)
        update_root = app_dir / "updates"
        stage = update_root / safe_version
        cleanup_old_updates(update_root, keep=stage)
        stage.mkdir(parents=True, exist_ok=True)

        manifest_asset = _asset(release, MANIFEST_ASSET, min_size=2)
        manifest_path = stage / MANIFEST_ASSET
        download_verified(manifest_asset, manifest_path, session=session)
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise RuntimeError("update_manifest_json_invalid") from exc
        manifest_assets = validate_manifest(manifest, new_version)

        resolved_assets: list[dict] = []
        total_bytes = 0
        for item in manifest_assets:
            asset = _asset(release, item["name"], min_size=100_000)
            total_bytes += int(asset["size"])
            resolved_assets.append({**item, "asset": asset})
        _ensure_disk_space(stage, total_bytes)

        plan_assets: list[dict] = []
        gateway_source: pathlib.Path | None = None
        updater_source: pathlib.Path | None = None
        for item in resolved_assets:
            source = stage / item["name"]
            digest = download_verified(item["asset"], source, session=session)
            entry = {
                "name": item["name"],
                "target": item["target"],
                "role": item["role"],
                "source": str(source),
                "sha256": digest,
            }
            plan_assets.append(entry)
            if item["role"] == "gateway":
                gateway_source = source
            elif item["role"] == "updater":
                updater_source = source

        if gateway_source is None or updater_source is None:
            raise RuntimeError("update_manifest_core_assets_missing")

        # The staged Gateway must authenticate to recorder + cloud before the
        # currently working process is allowed to stop.
        preflight_env = os.environ.copy()
        preflight_env["ZHIROX_PREFLIGHT_REPORT_VERSION"] = current_version
        preflight = subprocess.run(
            [str(gateway_source), "--preflight-update"],
            capture_output=True,
            timeout=45,
            env=preflight_env,
            creationflags=_hidden_flags(),
        )
        if preflight.returncode != 0:
            raise RuntimeError(f"update_preflight_failed:{preflight.returncode}")

        plan = {
            "schema": 1,
            "protocol": UPDATE_PROTOCOL,
            "from_version": current_version,
            "to_version": new_version,
            "task_name": TASK_NAME,
            "health_timeout_seconds": int(manifest.get("health_timeout_seconds") or 90),
            "assets": plan_assets,
        }
        plan_path = stage / "apply-plan.json"
        temp_plan = plan_path.with_suffix(".json.tmp")
        temp_plan.write_text(json.dumps(plan, sort_keys=True), encoding="utf-8")
        os.replace(temp_plan, plan_path)

        args = [
            str(updater_source),
            "--apply-plan", str(plan_path),
            "--parent-pid", str(os.getpid()),
            "--install-dir", str(installed_gateway.parent),
        ]
        subprocess.Popen(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            creationflags=_detached_flags(),
        )
        handed_off = True
        log(
            f"auto_update_staged from={current_version} to={new_version} "
            f"assets={len(plan_assets)}"
        )
        return True
    finally:
        if not handed_off:
            try:
                lock.unlink(missing_ok=True)
            except OSError:
                pass
