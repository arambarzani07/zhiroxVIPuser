import types
import unittest
from unittest.mock import Mock, patch

import transport_clock


class TransportRelayFastRetryTest(unittest.TestCase):
    def test_relay_failure_never_promotes_and_skips_exhaustive_ocr(self):
        original = Mock(
            return_value={
                'status': 'matched',
                'reason': 'exhaustive_verifier_must_not_run',
            }
        )
        agent = types.SimpleNamespace(verify_clip_time=original)

        class Client:
            def download_playback_stream(self, playback_uri, output_path, duration):
                return None

        transport_clock.install(agent, Client, Mock())
        hik = Client()
        hik._playback_codec_relay_used = True
        hik._playback_timing_attestation = {
            'verified': False,
            'reason': 'relay_failed',
            'relay_failed': True,
            'describe_accepted': True,
            'play_accepted': False,
            'range_kind': 'none',
            'sdp_corrected': True,
            'requested_duration_seconds': 30.0,
        }

        with patch.object(
            transport_clock,
            'verify_transport_contradiction',
            side_effect=AssertionError('fast guard requires verified transport'),
        ):
            result = agent.verify_clip_time(hik, 10, None, None, 30)

        original.assert_not_called()
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(result['reason'], 'transport_relay_failed_fast_retry')
        self.assertEqual(result['osd_guard_status'], 'skipped')
        self.assertTrue(result['transport_attestation']['relay_failed'])


if __name__ == '__main__':
    unittest.main()
