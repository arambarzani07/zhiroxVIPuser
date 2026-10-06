from __future__ import annotations

import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
from typing import Callable
from urllib.parse import urlsplit

import requests

REPOSITORY = "arambarzani07/zhiroxVIPuser"
RELEASES_URL = f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=30"
TAG_PREFIX = "hikvision-gateway-v"
GATEWAY_ASSET = "zhirox-hikvision-gateway.exe"
UPDATER_ASSET = "zhirox-hikvision-updater.exe"
CHECK_INTERVAL_SECONDS = 30 * 60
TASK_NAME = "ZHIROX Hikvision Gateway"

_HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2026-03-10",
    "User-Agent": "ZHIROX-Hikvision-Gateway",
}


def version_tuple(value: str) -> tuple[int, int, int]:
    match = re.search(r"(?:^|v)(\d+)\.(\d+)\.(\d+)", value)
    if not match:
        raise ValueError("invalid_gateway_version")
    return tuple(int(part) for part in match.groups())


def _release_version(release: dict) -> str | None:
    tag = str(release.get("tag_name") or "")
    if not tag.startswith(TAG_PREFIX):
        return None
    return tag[len(TAG_PREFIX):]


def find_newer_release(current_version: str, session=requests) -> dict | None:
    response = session.get(RELEASES_URL, headers=_HEADERS, timeout=(8, 20))
    response.raise_for_status()
    current = version_tuple(current_version)
    candidates: list[tuple[tuple[int, int, int], dict]] = []
    for release in response.json():
        if release.get("draft") or release.get("prerelease"):
            continue
        version = _release_version(release)
        if not version:
            continue
        parsed = version_tuple(version)
        if parsed > current:
            release = dict(release)
            release["_gateway_version"] = version
            candidates.append((parsed, release))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def _asset(release: dict, name: str) -> dict:
    for asset in release.get("assets") or []:
        if asset.get("name") == name:
            digest = str(asset.get("digest") or "")
            if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
                raise RuntimeError(f"update_asset_digest_missing:{name}")
            if int(asset.get("size") or 0) < 100_000:
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
    temp.unlink(missing_ok=True)
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
    if temp.stat().st_size != expected_size:
        temp.unlink(missing_ok=True)
        raise RuntimeError("update_asset_size_mismatch")
    actual = _sha256(temp)
    if actual != expected:
        temp.unlink(missing_ok=True)
        raise RuntimeError("update_asset_sha256_mismatch")
    os.replace(temp, destination)
    return expected


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

    new_version = str(release["_gateway_version"])
    safe_version = re.sub(r"[^0-9A-Za-z._+-]", "_", new_version)
    update_root = app_dir / "updates"
    stage = update_root / safe_version
    cleanup_old_updates(update_root, keep=stage)
    stage.mkdir(parents=True, exist_ok=True)

    gateway_asset = _asset(release, GATEWAY_ASSET)
    updater_asset = _asset(release, UPDATER_ASSET)
    staged_gateway = stage / GATEWAY_ASSET
    staged_updater = stage / UPDATER_ASSET
    gateway_sha = download_verified(gateway_asset, staged_gateway, session=session)
    updater_sha = download_verified(updater_asset, staged_updater, session=session)

    # The staged binary must authenticate to both the recorder and cloud before
    # it is allowed to replace the currently working executable. It never claims
    # a job in this mode. Report the currently installed version during preflight
    # so cloud health never claims a version that is not installed yet.
    preflight_env = os.environ.copy()
    preflight_env["ZHIROX_PREFLIGHT_REPORT_VERSION"] = current_version
    preflight = subprocess.run(
        [str(staged_gateway), "--preflight-update"],
        capture_output=True,
        timeout=45,
        env=preflight_env,
        creationflags=_hidden_flags(),
    )
    if preflight.returncode != 0:
        raise RuntimeError(f"update_preflight_failed:{preflight.returncode}")

    installed_updater = installed_gateway.parent / UPDATER_ASSET
    args = [
        str(staged_updater),
        "--apply",
        "--parent-pid", str(os.getpid()),
        "--current", str(installed_gateway),
        "--new", str(staged_gateway),
        "--sha256", gateway_sha,
        "--installed-updater", str(installed_updater),
        "--new-updater", str(staged_updater),
        "--updater-sha256", updater_sha,
        "--task-name", TASK_NAME,
        "--from-version", current_version,
        "--to-version", new_version,
    ]
    subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        close_fds=True,
        creationflags=_detached_flags(),
    )
    log(f"auto_update_staged from={current_version} to={new_version}")
    return True
