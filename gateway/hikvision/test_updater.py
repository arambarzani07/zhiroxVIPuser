import hashlib
import json
import pathlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

import updater


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class UpdaterHardeningTest(unittest.TestCase):
    def test_safe_target_supports_subfolders_but_blocks_escape_and_devices(self):
        self.assertEqual(
            updater._safe_relative_target('runtime/models/model.dat'),
            'runtime/models/model.dat',
        )
        for bad in ('../evil.exe', 'runtime/../evil.exe', r'runtime\\evil.exe', 'C:/evil.exe', 'runtime/CON.dat'):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(RuntimeError, 'target_invalid'):
                    updater._safe_relative_target(bad)

    def test_plan_accepts_tiny_companion_and_nested_target(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            stage = root / 'stage'
            install = root / 'install'
            stage.mkdir()
            install.mkdir()

            gateway = stage / 'gateway.exe'
            update_exe = stage / 'updater.exe'
            companion = stage / 'model.dat'
            gateway.write_bytes(b'g' * 100_001)
            update_exe.write_bytes(b'u' * 100_001)
            companion.write_bytes(b'x')

            plan_path = stage / 'apply-plan.json'
            plan_path.write_text(json.dumps({
                'schema': 1,
                'protocol': 1,
                'from_version': '1.4.0+evergreen-1',
                'to_version': '1.4.1+evergreen-1',
                'release_commit': 'a' * 40,
                'task_name': updater.TASK_NAME_DEFAULT,
                'health_timeout_seconds': 90,
                'assets': [
                    {
                        'name': gateway.name,
                        'source': str(gateway),
                        'target': 'zhirox-hikvision-gateway.exe',
                        'role': 'gateway',
                        'sha256': digest(gateway),
                    },
                    {
                        'name': update_exe.name,
                        'source': str(update_exe),
                        'target': 'zhirox-hikvision-updater.exe',
                        'role': 'updater',
                        'sha256': digest(update_exe),
                    },
                    {
                        'name': companion.name,
                        'source': str(companion),
                        'target': 'runtime/models/model.dat',
                        'role': 'companion',
                        'sha256': digest(companion),
                    },
                ],
            }), encoding='utf-8')

            plan = updater._load_plan(plan_path, install)
            nested = next(x for x in plan['assets'] if x['role'] == 'companion')
            self.assertEqual(
                nested['target'],
                (install / 'runtime/models/model.dat').resolve(),
            )
            self.assertEqual(nested['min_size'], 1)

    def test_atomic_install_and_rollback_restore_previous_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / 'new.bin'
            target = root / 'runtime' / 'data.bin'
            target.parent.mkdir()
            source.write_bytes(b'new-data')
            target.write_bytes(b'old-data')

            record = updater.atomic_install(source, target, digest(source), min_size=1)
            self.assertEqual(target.read_bytes(), b'new-data')
            self.assertTrue(record['backup'].exists())

            updater.rollback_assets([record])
            self.assertEqual(target.read_bytes(), b'old-data')

    def test_journal_recovers_asset_replaced_just_before_power_loss(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            install = pathlib.Path(temp_dir)
            target = install / 'zhirox-hikvision-gateway.exe'
            target.write_bytes(b'new-gateway')
            journal = {
                'records': [],
                'current_asset': {
                    'target': target.name,
                    'existed': False,
                    'sha256': digest(target),
                },
            }
            records = updater._journal_records(journal, install)
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]['target'], target.resolve())

    def test_recovery_task_xml_is_hidden_and_runs_before_gateway_delay(self):
        xml = updater._recovery_task_xml(
            pathlib.Path('/tmp/updater.exe'),
            pathlib.Path('/tmp/apply-plan.json'),
            pathlib.Path('/tmp/install'),
            'TEST\\user',
        )
        root = ET.fromstring(xml)
        text = xml
        self.assertIn('<Delay>PT2S</Delay>', text)
        self.assertIn('<Hidden>true</Hidden>', text)
        self.assertIn('--recover-plan', text)
        self.assertEqual(root.tag.rsplit('}', 1)[-1], 'Task')


if __name__ == '__main__':
    unittest.main()
