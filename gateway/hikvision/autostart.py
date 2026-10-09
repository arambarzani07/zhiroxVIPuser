from __future__ import annotations

import getpass
import html
import pathlib
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone

TASK_NAME = "ZHIROX Hikvision Gateway"


def current_windows_user() -> str:
    try:
        result = subprocess.run(
            ["whoami"], capture_output=True, text=True, timeout=10, check=True
        )
        value = result.stdout.strip()
        if value:
            return value
    except Exception:
        pass
    return getpass.getuser()


def task_xml(agent_exe: pathlib.Path, user_id: str) -> str:
    command = html.escape(str(agent_exe.resolve()))
    user = html.escape(user_id)
    recovery_start = (datetime.now(timezone.utc) + timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return f'''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>ZHIROX Hikvision Gateway resilient background task</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>{recovery_start}</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>{user}</UserId>
      <Delay>PT10S</Delay>
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
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>4</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{command}</Command>
    </Exec>
  </Actions>
</Task>
'''


def install_resilient_task(agent_exe: pathlib.Path) -> None:
    if not agent_exe.exists():
        raise RuntimeError(f"gateway_exe_not_found:{agent_exe}")
    user_id = current_windows_user()
    xml = task_xml(agent_exe, user_id)
    temp_path: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".xml", encoding="utf-16", delete=False
        ) as fh:
            fh.write(xml)
            temp_path = pathlib.Path(fh.name)
        result = subprocess.run(
            ["schtasks", "/Create", "/F", "/TN", TASK_NAME, "/XML", str(temp_path)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                (result.stderr or result.stdout).strip() or "scheduled_task_failed"
            )
    finally:
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except Exception:
                pass


def start_task() -> None:
    result = subprocess.run(
        ["schtasks", "/Run", "/TN", TASK_NAME],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if result.returncode != 0:
        text = (result.stderr or result.stdout).strip().lower()
        if "already running" not in text:
            raise RuntimeError(text or "scheduled_task_start_failed")


def locate_agent() -> pathlib.Path:
    base = pathlib.Path(sys.executable).resolve().parent
    return base / "zhirox-hikvision-gateway.exe"


def main() -> int:
    print("ZHIROX Hikvision Gateway Auto-start Repair")
    agent = locate_agent()
    install_resilient_task(agent)
    start_task()
    print("Resilient auto-start installed and Gateway start requested.")
    print("The Gateway starts after Windows logon; a recurring check restarts it if stopped.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Auto-start setup failed: {type(exc).__name__}: {exc}")
        raise SystemExit(1)

