import pathlib
import tempfile
import time
import unittest
from unittest import mock

import maintenance


class MaintenanceTest(unittest.TestCase):
    def test_rotate_file_keeps_bounded_backups(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            log = root / 'gateway.log'
            log.write_bytes(b'a' * 20)
            maintenance.rotate_file(log, max_bytes=10, backups=2)
            self.assertFalse(log.exists())
            self.assertTrue((root / 'gateway.log.1').exists())

            log.write_bytes(b'b' * 20)
            maintenance.rotate_file(log, max_bytes=10, backups=2)
            self.assertEqual((root / 'gateway.log.1').read_bytes(), b'b' * 20)
            self.assertEqual((root / 'gateway.log.2').read_bytes(), b'a' * 20)

    def test_cleanup_stale_temp_removes_only_old_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            old_file = root / 'old.raw.mp4'
            fresh_file = root / 'fresh.mp4'
            old_file.write_bytes(b'old')
            fresh_file.write_bytes(b'fresh')
            now = time.time()
            old_time = now - maintenance.TEMP_MAX_AGE_SECONDS - 10
            old_file.touch()
            fresh_file.touch()
            import os
            os.utime(old_file, (old_time, old_time))

            with mock.patch.object(maintenance, 'TEMP_DIR', root):
                removed = maintenance.cleanup_stale_temp(now=now)
            self.assertEqual(removed, 1)
            self.assertFalse(old_file.exists())
            self.assertTrue(fresh_file.exists())

    def test_orphan_cleanup_is_suppressed_while_update_is_active(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            orphan = root / 'helper.exe.incoming'
            orphan.write_bytes(b'x')
            now = time.time()
            old_time = now - maintenance.ORPHAN_MAX_AGE_SECONDS - 10
            import os
            os.utime(orphan, (old_time, old_time))

            with mock.patch.object(maintenance, 'update_in_progress', return_value=True):
                removed = maintenance.cleanup_orphan_install_files(root, now=now)
            self.assertEqual(removed, 0)
            self.assertTrue(orphan.exists())

            with mock.patch.object(maintenance, 'update_in_progress', return_value=False):
                removed = maintenance.cleanup_orphan_install_files(root, now=now)
            self.assertEqual(removed, 1)
            self.assertFalse(orphan.exists())


if __name__ == '__main__':
    unittest.main()
