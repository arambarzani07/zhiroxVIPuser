from __future__ import annotations

import getpass
import os
import pathlib
import sys

from autostart import install_resilient_task, start_task
from common import CONFIG_PATH, CloudClient, GatewayConfig, HikvisionClient


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


def main() -> int:
    print("ZHIROX Hikvision Gateway Setup")
    print("NVR password and gateway token are encrypted locally with Windows DPAPI.")
    print("They are never written to Supabase or GitHub.\n")

    host = ask("NVR address", "192.168.1.2")
    username = ask("NVR username", "admin")
    password = ask_secret("NVR password (typing shows *): ")
    token = ask_secret("ZHIROX gateway token (typing shows *): ")
    if not password or len(token) < 32:
        print("Password or gateway token is missing.")
        return 2

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

    cfg.save()
    print(f"Encrypted config saved to: {CONFIG_PATH}")

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
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print(f"Setup failed: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
