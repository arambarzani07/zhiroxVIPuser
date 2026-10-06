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


class SelfUpdateTest(unittest.TestCase):
    def test_version_tuple_ignores_build_metadata(self):
        self.assertEqual(self_update.version_tuple('1.3.4+auto-update-1'), (1, 3, 4))
        self.assertEqual(self_update.version_tuple('v2.10.7'), (2, 10, 7))

    def test_release_selection_ignores_unrelated_user_releases(self):
        payload = [
            {'tag_name': 'user-r9999-deadbee', 'draft': False, 'prerelease': False},
            {'tag_name': 'hikvision-gateway-v1.3.5+fix-1', 'draft': False, 'prerelease': False, 'assets': []},
            {'tag_name': 'hikvision-gateway-v1.4.0+fix-1', 'draft': False, 'prerelease': False, 'assets': []},
            {'tag_name': 'hikvision-gateway-v9.0.0-beta', 'draft': False, 'prerelease': True, 'assets': []},
        ]
        release = self_update.find_newer_release('1.3.4+auto-update-1', FakeSession(payload))
        self.assertIsNotNone(release)
        self.assertEqual(release['_gateway_version'], '1.4.0+fix-1')

    def test_no_downgrade_or_same_version(self):
        payload = [
            {'tag_name': 'hikvision-gateway-v1.3.4+other-build', 'draft': False, 'prerelease': False, 'assets': []},
            {'tag_name': 'hikvision-gateway-v1.3.3+old', 'draft': False, 'prerelease': False, 'assets': []},
        ]
        self.assertIsNone(
            self_update.find_newer_release('1.3.4+auto-update-1', FakeSession(payload))
        )

    def test_asset_requires_github_digest_and_repo_url(self):
        good = {
            'assets': [{
                'name': self_update.GATEWAY_ASSET,
                'digest': 'sha256:' + ('a' * 64),
                'size': 1_000_000,
                'browser_download_url': (
                    'https://github.com/arambarzani07/zhiroxVIPuser/'
                    'releases/download/hikvision-gateway-v1.3.5/'
                    'zhirox-hikvision-gateway.exe'
                ),
            }]
        }
        asset = self_update._asset(good, self_update.GATEWAY_ASSET)
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


if __name__ == '__main__':
    unittest.main()
