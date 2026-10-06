import json
import pathlib
import tempfile
import unittest
from datetime import datetime, timezone

import self_update


class FakeResponse:
    def __init__(self, payload, url='https://api.github.com/test'):
        self._payload = payload
        self.url = url

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


class ReleaseSession:
    def __init__(self, pages):
        self.pages = pages
        self.calls = []

    def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        page = 1
        if 'page=' in url:
            page = int(url.rsplit('page=', 1)[1].split('&', 1)[0])
        return FakeResponse(self.pages.get(page, []), url=url)


class ProvenanceSession:
    def __init__(self, runs):
        self.runs = runs
        self.calls = []

    def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return FakeResponse({'workflow_runs': self.runs}, url=url)


def manifest_asset(version='1.4.1+evergreen-1'):
    return {
        'name': self_update.MANIFEST_ASSET,
        'digest': 'sha256:' + ('b' * 64),
        'size': 500,
        'browser_download_url': (
            'https://github.com/arambarzani07/zhiroxVIPuser/'
            f'releases/download/hikvision-gateway-v{version}/gateway-update.json'
        ),
    }


def gateway_release(version, *, assets=None, draft=False, prerelease=False):
    return {
        'tag_name': f'hikvision-gateway-v{version}',
        'draft': draft,
        'prerelease': prerelease,
        'assets': assets if assets is not None else [manifest_asset(version)],
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
            gateway_release('1.4.0+evergreen-2'),
            gateway_release('1.5.0+evergreen-1', assets=[]),
            gateway_release('9.0.0-beta', prerelease=True),
        ]
        release = self_update.find_newer_release(
            '1.4.0+evergreen-1', ReleaseSession({1: payload})
        )
        self.assertIsNotNone(release)
        self.assertEqual(release['_gateway_version'], '1.4.0+evergreen-2')

    def test_release_discovery_paginates_past_unrelated_app_releases(self):
        unrelated = [
            {'tag_name': f'user-r{i}-deadbee', 'draft': False, 'prerelease': False}
            for i in range(self_update.RELEASE_PAGE_SIZE)
        ]
        session = ReleaseSession({
            1: unrelated,
            2: [gateway_release('1.4.2+evergreen-1')],
        })
        release = self_update.find_newer_release('1.4.1+evergreen-1', session)
        self.assertIsNotNone(release)
        self.assertEqual(release['_gateway_version'], '1.4.2+evergreen-1')
        self.assertEqual(len(session.calls), 2)

    def test_no_downgrade_or_same_revision(self):
        payload = [
            gateway_release('1.4.0+evergreen-1'),
            gateway_release('1.3.9+evergreen-99'),
        ]
        self.assertIsNone(
            self_update.find_newer_release(
                '1.4.0+evergreen-1', ReleaseSession({1: payload})
            )
        )

    def test_release_provenance_requires_bot_and_successful_production_ci(self):
        commit = 'a' * 40
        release = {
            'author': {'login': self_update.PUBLISHER_LOGIN},
            'target_commitish': commit,
        }
        good_run = {
            'head_sha': commit,
            'head_branch': 'user-source',
            'path': self_update.PUBLISH_WORKFLOW,
            'event': 'push',
            'status': 'completed',
            'conclusion': 'success',
        }
        result = self_update.verify_release_provenance(
            release, ProvenanceSession([good_run])
        )
        self.assertEqual(result, commit)

        bad_publisher = dict(release, author={'login': 'someone-else'})
        with self.assertRaisesRegex(RuntimeError, 'publisher_rejected'):
            self_update.verify_release_provenance(
                bad_publisher, ProvenanceSession([good_run])
            )

        bad_run = dict(good_run, path='.github/workflows/other.yml')
        with self.assertRaisesRegex(RuntimeError, 'ci_provenance_missing'):
            self_update.verify_release_provenance(
                release, ProvenanceSession([bad_run])
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

    def test_manifest_allows_small_future_companions_and_safe_subfolders(self):
        manifest = {
            'schema': 1,
            'protocol': 1,
            'version': '1.4.1+evergreen-1',
            'assets': [
                {
                    'name': 'zhirox-hikvision-updater.exe',
                    'target': 'zhirox-hikvision-updater.exe',
                    'role': 'updater',
                },
                {
                    'name': 'model.dat',
                    'target': 'runtime/models/model.dat',
                    'role': 'companion',
                },
                {
                    'name': 'zhirox-hikvision-gateway.exe',
                    'target': 'zhirox-hikvision-gateway.exe',
                    'role': 'gateway',
                },
            ],
        }
        assets = self_update.validate_manifest(manifest, '1.4.1+evergreen-1')
        self.assertEqual(len(assets), 3)
        self.assertEqual(assets[1]['target'], 'runtime/models/model.dat')
        self.assertEqual({item['role'] for item in assets}, {'gateway', 'updater', 'companion'})

    def test_manifest_rejects_path_traversal_reserved_names_and_missing_core(self):
        base = {
            'schema': 1,
            'protocol': 1,
            'version': '1.4.1+evergreen-1',
        }
        bad_path = dict(base, assets=[
            {'name': 'updater.exe', 'target': '../updater.exe', 'role': 'updater'},
            {'name': 'gateway.exe', 'target': 'gateway.exe', 'role': 'gateway'},
        ])
        with self.assertRaisesRegex(RuntimeError, 'target_invalid'):
            self_update.validate_manifest(bad_path, '1.4.1+evergreen-1')

        reserved = dict(base, assets=[
            {'name': 'updater.exe', 'target': 'updater.exe', 'role': 'updater'},
            {'name': 'helper.dat', 'target': 'runtime/CON.dat', 'role': 'companion'},
            {'name': 'gateway.exe', 'target': 'gateway.exe', 'role': 'gateway'},
        ])
        with self.assertRaisesRegex(RuntimeError, 'target_invalid'):
            self_update.validate_manifest(reserved, '1.4.1+evergreen-1')

        missing_updater = dict(base, assets=[
            {'name': 'helper.exe', 'target': 'helper.exe', 'role': 'companion'},
            {'name': 'gateway.exe', 'target': 'gateway.exe', 'role': 'gateway'},
        ])
        with self.assertRaisesRegex(RuntimeError, 'core_assets_missing'):
            self_update.validate_manifest(missing_updater, '1.4.1+evergreen-1')

    def test_rolled_back_release_is_temporarily_quarantined(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = pathlib.Path(temp_dir)
            state = {
                'status': 'rolled_back',
                'to_version': '1.4.2+evergreen-1',
                'rolled_back_at': datetime.now(timezone.utc).isoformat(),
            }
            (app_dir / 'last_update.json').write_text(
                json.dumps(state), encoding='utf-8'
            )
            self.assertTrue(
                self_update._is_quarantined(app_dir, '1.4.2+evergreen-1')
            )
            self.assertFalse(
                self_update._is_quarantined(app_dir, '1.4.3+evergreen-1')
            )


if __name__ == '__main__':
    unittest.main()
