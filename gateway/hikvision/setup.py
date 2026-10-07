from __future__ import annotations

import getpass
import os
import pathlib
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
