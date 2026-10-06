from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

REPO = "arambarzani07/zhiroxVIPuser"
LATEST_RELEASE_API = f"https://api.github.com/repos/{REPO}/releases/latest"
GATEWAY_NAME = "zhirox-hikvision-gateway.exe"
CHECKSUM_NAME = "zhirox-hikvision-gateway.sha256"
USER_AGENT = "ZHIROX-Hikvision-Gateway-Updater/1.0"


def _base_dir() -> pathlib.Path:
    return pathlib.Path(sys.executable).resolve().parent


def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _get(url: str, timeout: int = 45) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"update_http_{response.status}")
            return response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"update_http_{exc.code}") from None
    except (urllib.error.URLError, OSError, TimeoutError):
        raise RuntimeError("update_network_error") from None


def _latest_assets() -> dict[str, str]:
    payload = json.loads(_get(LATEST_RELEASE_API).decode("utf-8"))
    assets = payload.get("assets") or []
    result: dict[str, str] = {}
    for asset in assets:
        name = str(asset.get("name") or "")
        url = str(asset.get("browser_download_url") or "")
        if name and url.startswith("https://github.com/"):
            result[name] = url
    return result


def _expected_sha256(assets: dict[str, str]) -> str:
    url = assets.get(CHECKSUM_NAME)
    if not url:
        raise RuntimeError("update_checksum_missing")
    text = _get(url).decode("ascii", errors="strict").strip().lower()
    token = text.split()[0] if text else ""
    if len(token) != 64 or any(ch not in "0123456789abcdef" for ch in token):
        raise RuntimeError("update_checksum_invalid")
    return token


def _download_verified(assets: dict[str, str], expected: str, destination: pathlib.Path) -> None:
    url = assets.get(GATEWAY_NAME)
    if not url:
        raise RuntimeError("update_gateway_asset_missing")
    payload = _get(url, timeout=180)
    destination.write_bytes(payload)
    actual = _sha256(destination)
    if actual != expected:
        destination.unlink(missing_ok=True)
        raise RuntimeError("update_sha256_mismatch")


def _install_atomic(target: pathlib.Path, staged: pathlib.Path) -> None:
    backup = target.with_suffix(target.suffix + ".previous")
    if backup.exists():
        backup.unlink()
    if target.exists():
        target.replace(backup)
    try:
        staged.replace(target)
    except Exception:
        if backup.exists() and not target.exists():
            backup.replace(target)
        raise


def _gateway_running() -> bool:
    if os.name != "nt":
        return False
    completed = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {GATEWAY_NAME}", "/NH"],
        capture_output=True,
        text=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        check=False,
    )
    return GATEWAY_NAME.lower() in completed.stdout.lower()


def _start_gateway(target: pathlib.Path) -> None:
    if not target.exists() or _gateway_running():
        return
    flags = 0
    if os.name == "nt":
        flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    subprocess.Popen(
        [str(target)],
        cwd=str(target.parent),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=flags,
        close_fds=True,
    )


def main() -> int:
    base = _base_dir()
    target = base / GATEWAY_NAME
    try:
        assets = _latest_assets()
        expected = _expected_sha256(assets)
        current = _sha256(target) if target.exists() else ""
        if current != expected:
            # Do not replace a live recorder process. The update will be applied
            # automatically on the next logon/startup when the gateway is idle.
            if not _gateway_running():
                with tempfile.TemporaryDirectory(prefix="zhirox-gateway-update-") as tmp:
                    staged = pathlib.Path(tmp) / GATEWAY_NAME
                    _download_verified(assets, expected, staged)
                    _install_atomic(target, staged)
    except Exception:
        # Update availability must never prevent the gateway from starting.
        pass

    _start_gateway(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
