import unittest

import self_update
import update_policy


class FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


class FakeSession:
    def __init__(self, pages):
        self.pages = pages
        self.calls = []

    def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        page = 1
        if 'page=' in url:
            page = int(url.rsplit('page=', 1)[1].split('&', 1)[0])
        return FakeResponse(self.pages.get(page, []))


def manifest_asset(version):
    return {
        'name': self_update.MANIFEST_ASSET,
        'digest': 'sha256:' + ('a' * 64),
        'size': 400,
        'browser_download_url': (
            'https://github.com/arambarzani07/zhiroxVIPuser/'
            f'releases/download/hikvision-gateway-v{version}/gateway-update.json'
        ),
    }


def release(version):
    return {
        'tag_name': f'hikvision-gateway-v{version}',
        'draft': False,
        'prerelease': False,
        'assets': [manifest_asset(version)],
    }


class UpdatePolicyTest(unittest.TestCase):
    def test_selects_oldest_required_release_for_bridge_compatibility(self):
        session = FakeSession({1: [
            release('1.6.0+evergreen-1'),
            release('1.5.0+evergreen-1'),
            release('1.4.2+evergreen-1'),
            release('1.4.1+evergreen-1'),
            release('1.4.0+evergreen-1'),
        ]})
        selected = update_policy.find_next_release('1.4.0+evergreen-1', session)
        self.assertIsNotNone(selected)
        self.assertEqual(selected['_gateway_version'], '1.4.1+evergreen-1')

    def test_scans_across_unrelated_release_pages_until_installed_baseline(self):
        unrelated = [
            {'tag_name': f'user-r{i}-deadbee', 'draft': False, 'prerelease': False}
            for i in range(self_update.RELEASE_PAGE_SIZE)
        ]
        session = FakeSession({
            1: unrelated,
            2: [
                release('1.4.2+evergreen-1'),
                release('1.4.1+evergreen-1'),
                release('1.4.0+evergreen-1'),
            ],
        })
        selected = update_policy.find_next_release('1.4.0+evergreen-1', session)
        self.assertIsNotNone(selected)
        self.assertEqual(selected['_gateway_version'], '1.4.1+evergreen-1')
        self.assertEqual(len(session.calls), 2)

    def test_ignores_draft_prerelease_and_manifestless_versions(self):
        bad_draft = release('1.4.1+evergreen-1')
        bad_draft['draft'] = True
        bad_pre = release('1.4.2+evergreen-1')
        bad_pre['prerelease'] = True
        no_manifest = release('1.4.3+evergreen-1')
        no_manifest['assets'] = []
        session = FakeSession({1: [
            no_manifest,
            bad_pre,
            bad_draft,
            release('1.4.0+evergreen-1'),
        ]})
        self.assertIsNone(
            update_policy.find_next_release('1.4.0+evergreen-1', session)
        )


if __name__ == '__main__':
    unittest.main()
