import pathlib
import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import MagicMock, patch

import autostart
import bootstrap


class EndLoop(BaseException):
    pass


class ConnectionRecoveryTests(unittest.TestCase):
    def test_running_windows_payload_refreshes_existing_task_without_launching_worker(self):
        with patch.object(bootstrap.os, 'name', 'nt'), patch.object(
            bootstrap.sys, 'frozen', True, create=True
        ), patch.object(bootstrap, '_installed_gateway_path', return_value='installed-gateway.exe'), patch.object(
            bootstrap, 'install_resilient_task'
        ) as install, patch.object(bootstrap, 'log'):
            bootstrap._repair_resilient_autostart()
            install.assert_called_once_with('installed-gateway.exe')

    def test_task_repair_failure_does_not_stop_network_recovery(self):
        with patch.object(bootstrap.os, 'name', 'nt'), patch.object(
            bootstrap.sys, 'frozen', True, create=True
        ), patch.object(bootstrap, '_installed_gateway_path', return_value='installed-gateway.exe'), patch.object(
            bootstrap, 'install_resilient_task', side_effect=PermissionError()
        ), patch.object(bootstrap, 'log') as log:
            bootstrap._repair_resilient_autostart()
            log.assert_called_once_with('autostart_periodic_recovery_error=PermissionError')

    def test_cloud_outage_recovers_without_restarting_or_claiming_jobs(self):
        calls = []
        clients = []
        markers = []
        sleeps = []

        def fresh_client(cfg):
            client = MagicMock()
            clients.append(client)
            def call(action):
                calls.append(action)
                # Startup succeeds, two subsequent probes fail, then recover.
                if len(calls) in (2, 3):
                    raise ConnectionError('network unavailable')
                return {'ok': True}
            client.call.side_effect = call
            return client

        def sleep(seconds):
            sleeps.append(seconds)
            if len(sleeps) == 3:
                raise EndLoop()

        with tempfile.TemporaryDirectory() as td:
            config = pathlib.Path(td) / 'config.json'
            config.touch()
            with patch.object(bootstrap, 'CONFIG_PATH', config), patch.object(
                bootstrap.GatewayConfig, 'load', return_value=object()
            ), patch.object(bootstrap, 'HikvisionClient') as hik, patch.object(
                bootstrap, 'CloudClient', side_effect=fresh_client
            ), patch.object(bootstrap, '_write_health', side_effect=lambda: markers.append(True)), patch.object(
                bootstrap.time, 'sleep', side_effect=sleep
            ), patch.object(bootstrap, 'log'):
                with self.assertRaises(EndLoop):
                    bootstrap._health_monitor_loop()

        self.assertEqual(calls, ['ping'] * 4)
        self.assertEqual(len(clients), 4)
        for client in clients:
            client.session.close.assert_called_once()
        self.assertEqual(len(markers), 2)
        self.assertEqual(sleeps, [15, 15, 30])
        hik.return_value.device_info.assert_called_once()

    def test_rejected_ping_is_retried_without_marking_healthy(self):
        with tempfile.TemporaryDirectory() as td:
            config = pathlib.Path(td) / 'config.json'
            config.touch()
            with patch.object(bootstrap, 'CONFIG_PATH', config), patch.object(
                bootstrap.GatewayConfig, 'load'
            ), patch.object(bootstrap, 'HikvisionClient'), patch.object(
                bootstrap, 'CloudClient'
            ) as cloud, patch.object(bootstrap, '_write_health') as health, patch.object(
                bootstrap.time, 'sleep', side_effect=EndLoop()
            ) as sleep, patch.object(bootstrap, 'log'):
                cloud.return_value.call.return_value = {'ok': False}
                with self.assertRaises(EndLoop):
                    bootstrap._health_monitor_loop()
                health.assert_not_called()
                sleep.assert_called_once_with(bootstrap.HEALTH_PROBE_RETRY_SECONDS)

    def test_background_ping_does_not_hide_a_stalled_capture_worker(self):
        with patch.object(bootstrap, '_last_worker_progress', 123), patch.object(
            bootstrap, '_original_cloud_call', return_value={'ok': True}
        ):
            bootstrap._patched_cloud_call(object(), 'ping')
            self.assertEqual(bootstrap._last_worker_progress, 123)

    def test_scheduled_recovery_keeps_checking_after_clean_process_exit(self):
        root = ET.fromstring(autostart.task_xml(pathlib.Path('gateway.exe'), 'test-user'))
        ns = {'t': 'http://schemas.microsoft.com/windows/2004/02/mit/task'}
        trigger = root.find('t:Triggers/t:TimeTrigger', ns)
        self.assertIsNotNone(trigger)
        self.assertEqual(trigger.findtext('t:Repetition/t:Interval', namespaces=ns), 'PT1M')
        self.assertIsNone(trigger.find('t:Repetition/t:Duration', ns))
        self.assertEqual(root.findtext('t:Settings/t:MultipleInstancesPolicy', namespaces=ns), 'IgnoreNew')
        self.assertEqual(root.findtext('t:Settings/t:RunOnlyIfNetworkAvailable', namespaces=ns), 'false')
        self.assertEqual(root.findtext('t:Settings/t:WakeToRun', namespaces=ns), 'false')

    @unittest.skipUnless(sys.platform == 'win32', 'Windows Task Scheduler XML validation')
    def test_windows_accepts_recovery_task_xml_without_registering_it(self):
        with tempfile.TemporaryDirectory() as td:
            xml_path = pathlib.Path(td) / 'recovery.xml'
            xml_path.write_text(autostart.task_xml(
                pathlib.Path(sys.executable), autostart.current_windows_user()
            ), encoding='utf-16')
            env = dict(os.environ, ZHIROX_TEST_TASK_XML=str(xml_path))
            script = (
                "$ErrorActionPreference='Stop';"
                "$s=New-Object -ComObject Schedule.Service;$s.Connect();"
                "$xml=[IO.File]::ReadAllText($env:ZHIROX_TEST_TASK_XML);"
                # TASK_VALIDATE_ONLY=1 validates through the real scheduler
                # without saving a task or launching any application.
                "[void]$s.GetFolder('\\').RegisterTask('ZHIROX XML validation',$xml,1,$null,$null,3,$null)"
            )
            subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                           env=env, capture_output=True, check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
