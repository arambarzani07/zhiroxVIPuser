from __future__ import annotations

import getpass
import os
import pathlib
import subprocess
import sys
import traceback
from datetime import datetime, timezone

from autostart import install_resilient_task, start_task
from common import APP_DIR, CONFIG_PATH, CloudClient, GatewayConfig, HikvisionClient
from runtime_hardening import save_config_atomic

SETUP_ERROR_LOG = APP_DIR / "setup-error.log"


def ask(prompt: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{prompt}{suffix}: ").strip()
    return value or default


def ask_secret(prompt: str) -> str:
    """Echo a star for each typed or pasted character on Windows."""
    if os.name != "nt":
        return getpass.getpass(prompt)
    import msvcrt
    print(prompt, end="", flush=True)
    chars: list[str] = []
    while True:
        char = msvcrt.getwch()
        if char in ("\r", "\n"):
            print()
            return "".join(chars)
        if char == "\x03":
            raise KeyboardInterrupt
        if char in ("\x00", "\xe0"):
            msvcrt.getwch()
            continue
        if char == "\b":
            if chars:
                chars.pop()
                print("\b \b", end="", flush=True)
        elif char.isprintable():
            chars.append(char)
            print("*", end="", flush=True)


def load_existing_config() -> GatewayConfig | None:
    """Load the current DPAPI-protected configuration without exposing secrets."""
    if not CONFIG_PATH.exists():
        return None
    try:
        return GatewayConfig.load()
    except Exception as exc:
        print(
            "Warning: existing Gateway configuration could not be loaded; "
            f"new credentials are required ({type(exc).__name__})."
        )
        return None


def _desktop_dirs() -> list[pathlib.Path]:
    """Return the normal and OneDrive-backed Desktop locations for this user."""
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


def _current_setup_on_desktop() -> pathlib.Path | None:
    if os.name != "nt" or not getattr(sys, "frozen", False):
        return None
    current = pathlib.Path(sys.executable).resolve()
    for desktop in _desktop_dirs():
        try:
            if current.parent == desktop.resolve():
                return current
        except OSError:
            continue
    return None


def cleanup_stale_desktop_setups() -> None:
    """Remove only old ZHIROX Setup downloads; never touch unrelated files."""
    current = pathlib.Path(sys.executable).resolve() if getattr(sys, "frozen", False) else None
    for desktop in _desktop_dirs():
        if not desktop.exists():
            continue
        for candidate in desktop.glob("zhirox-hikvision-setup*.exe"):
            try:
                resolved = candidate.resolve()
                if current is not None and resolved == current:
                    continue
                candidate.unlink(missing_ok=True)
                print(f"Removed old Setup download: {candidate.name}")
            except OSError as exc:
                print(f"Warning: could not remove old Setup download {candidate.name}: {exc}")


def schedule_current_setup_cleanup() -> None:
    """If Setup itself was launched from Desktop, delete it after this process exits."""
    current = _current_setup_on_desktop()
    if current is None:
        return
    command = f'ping 127.0.0.1 -n 3 >nul & del /f /q "{current}"'
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.Popen(
        ["cmd.exe", "/d", "/c", command],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=flags,
        close_fds=True,
    )
    print("This Desktop Setup download will remove itself after closing.")


def setup_self_test() -> int:
    """Prove the frozen Setup contains all startup modules without using secrets/network."""
    APP_DIR.mkdir(parents=True, exist_ok=True)
    _ = (
        GatewayConfig,
        CloudClient,
        HikvisionClient,
        install_resilient_task,
        start_task,
        save_config_atomic,
        CONFIG_PATH,
    )
    print("setup_self_test=ok")
    return 0


def _write_error_log(exc: BaseException) -> None:
    """Persist startup/setup failures without recording entered credentials."""
    try:
        APP_DIR.mkdir(parents=True, exist_ok=True)
        with SETUP_ERROR_LOG.open("a", encoding="utf-8") as handle:
            handle.write(
                f"\n[{datetime.now(timezone.utc).isoformat()}] "
                f"{type(exc).__name__}: {exc}\n"
            )
            traceback.print_exc(file=handle)
    except Exception:
        pass


def _pause_on_failure() -> None:
    # A console EXE launched by double-click would otherwise disappear before
    # the operator can read the actual failure. CI self-test must never pause.
    if getattr(sys, "frozen", False) and "--self-test" not in sys.argv:
        try:
            input("Press Enter to close...")
        except (EOFError, KeyboardInterrupt):
            pass


def main() -> int:
    if "--self-test" in sys.argv:
        return setup_self_test()

    print("ZHIROX Hikvision Gateway Setup")
    print("NVR password and gateway token are encrypted locally with Windows DPAPI.")
    print("They are never written to Supabase or GitHub.\n")

    existing = load_existing_config()
    if existing is not None:
        print("Existing Gateway configuration detected.")
        print("Leave password/token blank to keep the currently saved encrypted value.\n")

    host = ask("NVR address", existing.nvr_host if existing else "192.168.1.3")
    username = ask("NVR username", existing.nvr_username if existing else "admin")

    password_input = ask_secret(
        "NVR password (blank keeps current; typing shows *): "
        if existing
        else "NVR password (typing shows *): "
    )
    token_input = ask_secret(
        "ZHIROX gateway token (blank keeps current; typing shows *): "
        if existing
        else "ZHIROX gateway token (typing shows *): "
    )

    password = password_input or (existing.nvr_password if existing else "")
    token = token_input or (existing.gateway_token if existing else "")
    if not password or len(token) < 32:
        print("Password or gateway token is missing.")
        return 2

    if existing is not None:
        cfg = GatewayConfig(host, username, password, token, existing.cloud_url)
    else:
        cfg = GatewayConfig(host, username, password, token)

    hik = HikvisionClient(cfg)
    cloud = CloudClient(cfg)

    print("Testing NVR ISAPI...")
    info = hik.device_info()
    if "DS-7616NI-K2" not in info and "Network Video Recorder" not in info:
        print("Warning: ISAPI answered, but the expected NVR model was not detected.")
    print("NVR ISAPI: OK")

    print("Testing secure cloud gateway...")
    ping = cloud.call("ping")
    if not ping.get("ok"):
        raise RuntimeError("cloud_gateway_ping_failed")
    print("Cloud gateway: OK")

    save_config_atomic(cfg)
    print(f"Encrypted config saved atomically to: {CONFIG_PATH}")

    base = pathlib.Path(sys.executable).resolve().parent
    agent = base / "zhirox-hikvision-gateway.exe"
    if agent.exists():
        answer = ask(
            "Install resilient auto-start and restart Gateway after crashes? (y/n)",
            "y",
        ).lower()
        if answer.startswith("y"):
            install_resilient_task(agent)
            start_task()
            print("Resilient auto-start installed and Gateway start requested.")
    else:
        print("Gateway EXE was not found beside the setup EXE; auto-start was skipped.")

    cleanup_stale_desktop_setups()
    schedule_current_setup_cleanup()
    print("Setup complete.")
    return 0


if __name__ == "__main__":
    try:
        result = main()
        if result != 0:
            _pause_on_failure()
        raise SystemExit(result)
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        _write_error_log(exc)
        print(f"Setup failed: {type(exc).__name__}: {exc}")
        print(f"Error log: {SETUP_ERROR_LOG}")
        _pause_on_failure()
        raise SystemExit(1)
