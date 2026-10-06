import unittest

import self_update


class FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


class FakeSession:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return FakeResponse(self.payload)


def manifest_asset():
    return {
        'name': self_update.MANIFEST_ASSET,
        'digest': 'sha256:' + ('b' * 64),
        'size': 500,
        'browser_download_url': (
            'https://github.com/arambarzani07/zhiroxVIPuser/'
            'releases/download/hikvision-gateway-v1.4.0/gateway-update.json'
        ),
    }


class SelfUpdateTest(unittest.TestCase):
    def test_version_key_orders_numeric_build_revision(self):
        self.assertEqual(self_update.version_key('1.4.0+evergreen-1'), (1, 4, 0, 1))
        self.assertEqual(self_update.version_key('v2.10.7'), (2, 10, 7, 0))
        self.assertGreater(
            self_update.version_key('1.4.0+evergreen-2'),
            self_update.version_key('1.4.0+evergreen-1'),
        )
        self.assertGreater(
            self_update.version_key('1.4.1'),
            self_update.version_key('1.4.0+evergreen-999'),
        )

    def test_release_selection_ignores_unrelated_and_legacy_releases(self):
        payload = [
            {'tag_name': 'user-r9999-deadbee', 'draft': False, 'prerelease': False},
            {
                'tag_name': 'hikvision-gateway-v1.4.0+evergreen-2',
                'draft': False,
                'prerelease': False,
                'assets': [manifest_asset()],
            },
            {
                'tag_name': 'hikvision-gateway-v1.5.0+evergreen-1',
                'draft': False,
                'prerelease': False,
                'assets': [],  # no evergreen manifest -> intentionally ignored
            },
            {
                'tag_name': 'hikvision-gateway-v9.0.0-beta',
                'draft': False,
                'prerelease': True,
                'assets': [manifest_asset()],
            },
        ]
        release = self_update.find_newer_release('1.4.0+evergreen-1', FakeSession(payload))
        self.assertIsNotNone(release)
        self.assertEqual(release['_gateway_version'], '1.4.0+evergreen-2')

    def test_no_downgrade_or_same_revision(self):
        payload = [
            {
                'tag_name': 'hikvision-gateway-v1.4.0+evergreen-1',
                'draft': False,
                'prerelease': False,
                'assets': [manifest_asset()],
            },
            {
                'tag_name': 'hikvision-gateway-v1.3.9+evergreen-99',
                'draft': False,
                'prerelease': False,
                'assets': [manifest_asset()],
            },
        ]
        self.assertIsNone(
            self_update.find_newer_release('1.4.0+evergreen-1', FakeSession(payload))
        )

    def test_asset_requires_github_digest_and_repo_url(self):
        good = {
            'assets': [{
                'name': self_update.GATEWAY_ASSET,
                'digest': 'sha256:' + ('a' * 64),
                'size': 1_000_000,
                'browser_download_url': (
                    'https://github.com/arambarzani07/zhiroxVIPuser/'
                    'releases/download/hikvision-gateway-v1.4.1/'
                    'zhirox-hikvision-gateway.exe'
                ),
            }]
        }
        asset = self_update._asset(good, self_update.GATEWAY_ASSET, min_size=100_000)
        self.assertEqual(asset['size'], 1_000_000)

        bad = {'assets': [dict(good['assets'][0], digest='')]}
        with self.assertRaisesRegex(RuntimeError, 'digest_missing'):
            self_update._asset(bad, self_update.GATEWAY_ASSET)

        bad_url = {'assets': [dict(
            good['assets'][0],
            browser_download_url='https://example.com/gateway.exe',
        )]}
        with self.assertRaisesRegex(RuntimeError, 'url_rejected'):
            self_update._asset(bad_url, self_update.GATEWAY_ASSET)

    def test_manifest_allows_future_companion_files(self):
        manifest = {
            'schema': 1,
            'protocol': 1,
            'version': '1.4.1+evergreen-1',
            'assets': [
                {'name': 'zhirox-hikvision-updater.exe', 'target': 'zhirox-hikvision-updater.exe', 'role': 'updater'},
                {'name': 'ffmpeg.exe', 'target': 'ffmpeg.exe', 'role': 'companion'},
                {'name': 'zhirox-hikvision-gateway.exe', 'target': 'zhirox-hikvision-gateway.exe', 'role': 'gateway'},
            ],
        }
        assets = self_update.validate_manifest(manifest, '1.4.1+evergreen-1')
        self.assertEqual(len(assets), 3)
        self.assertEqual({item['role'] for item in assets}, {'gateway', 'updater', 'companion'})

    def test_manifest_rejects_path_traversal_and_missing_core(self):
        bad_path = {
            'schema': 1,
            'protocol': 1,
            'version': '1.4.1+evergreen-1',
            'assets': [
                {'name': 'updater.exe', 'target': '../updater.exe', 'role': 'updater'},
                {'name': 'gateway.exe', 'target': 'gateway.exe', 'role': 'gateway'},
            ],
        }
        with self.assertRaisesRegex(RuntimeError, 'target_invalid'):
            self_update.validate_manifest(bad_path, '1.4.1+evergreen-1')

        missing_updater = {
            'schema': 1,
            'protocol': 1,
            'version': '1.4.1+evergreen-1',
            'assets': [
                {'name': 'helper.exe', 'target': 'helper.exe', 'role': 'companion'},
                {'name': 'gateway.exe', 'target': 'gateway.exe', 'role': 'gateway'},
            ],
        }
        with self.assertRaisesRegex(RuntimeError, 'core_assets_missing'):
            self_update.validate_manifest(missing_updater, '1.4.1+evergreen-1')


if __name__ == '__main__':
    unittest.main()
