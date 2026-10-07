import types
import unittest
from unittest.mock import Mock, patch

from rtsp_codec_relay import SdpCodecRelay
import transport_clock
import transport_spot_check


class RelayClockAttestationTests(unittest.TestCase):
    uri = (
        'rtsp://192.168.1.3/Streaming/tracks/1001'
        '?starttime=20261007T065519Z&endtime=20261007T065549Z'
    )

    def _relay(self):
        relay = SdpCodecRelay(self.uri, 'admin', 'secret')
        relay.local_authority = '127.0.0.1:12345'
        return relay

    def _accept_describe_with_correction(self, relay):
        local = (
            'rtsp://127.0.0.1:12345/Streaming/tracks/1001'
            '?starttime=20261007T065519Z&endtime=20261007T065549Z'
        )
        relay._request(f'DESCRIBE {local} RTSP/1.0\r\nCSeq: 1\r\n\r\n'.encode())
        body = (
            b'v=0\r\nm=video 0 RTP/AVP 96\r\n'
            b'a=rtpmap:96 H265/90000\r\na=control:trackID=1\r\n'
        )
        relay._response(
            b'RTSP/1.0 200 OK\r\nCSeq: 1\r\n'
            b'Content-Type: application/sdp\r\nContent-Length: '
            + str(len(body)).encode()
            + b'\r\n\r\n'
            + body
        )
        self.assertTrue(relay.corrected)

    def _play(self, relay, range_value):
        local = (
            'rtsp://127.0.0.1:12345/Streaming/tracks/1001'
            '?starttime=20261007T065519Z&endtime=20261007T065549Z'
        )
        relay._request(f'PLAY {local} RTSP/1.0\r\nCSeq: 2\r\n\r\n'.encode())
        header = b'RTSP/1.0 200 OK\r\nCSeq: 2\r\n'
        if range_value is not None:
            header += f'Range: {range_value}\r\n'.encode()
        relay._response(header + b'\r\n')

    def test_absolute_play_clock_match_is_verified(self):
        relay = self._relay()
        self._accept_describe_with_correction(relay)
        self._play(relay, 'clock=20261007T065519Z-20261007T065549Z')
        att = relay.timing_attestation()
        self.assertTrue(att['verified'])
        self.assertEqual(att['range_kind'], 'clock')
        self.assertEqual(att['start_delta_seconds'], 0)
        self.assertEqual(att['end_delta_seconds'], 0)
        self.assertNotIn('secret', str(att))
        self.assertNotIn(self.uri, str(att))

    def test_open_ended_absolute_start_is_verified_for_exact_duration_guard(self):
        relay = self._relay()
        self._accept_describe_with_correction(relay)
        self._play(relay, 'clock=20261007T065519Z-')
        att = relay.timing_attestation()
        self.assertTrue(att['verified'])
        self.assertFalse(att['range_end_present'])
        self.assertEqual(att['requested_duration_seconds'], 30)

    def test_npt_or_wrong_clock_never_verifies(self):
        for value, expected in (
            ('npt=0.000-', 'range_not_absolute_clock'),
            ('clock=20261007T055519Z-20261007T055549Z', 'clock_start_mismatch'),
            (None, 'range_absent'),
        ):
            with self.subTest(value=value):
                relay = self._relay()
                self._accept_describe_with_correction(relay)
                self._play(relay, value)
                att = relay.timing_attestation()
                self.assertFalse(att['verified'])
                self.assertEqual(att['reason'], expected)


class TransportSpotCheckTests(unittest.TestCase):
    def test_first_unknown_returns_unknown_without_second_expensive_scan(self):
        with patch.object(
            transport_spot_check,
            '_sample',
            return_value={'status': 'unknown', 'reason': 'clock_not_readable', 'sample_second': 0.0},
        ) as sample:
            result = transport_spot_check.verify_transport_spot_check(Mock(parent=Mock()), Mock(), 30)
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(sample.call_count, 1)

    def test_single_mismatch_is_not_enough_to_reject(self):
        with patch.object(
            transport_spot_check,
            '_sample',
            side_effect=[
                {'status': 'mismatch', 'offset_seconds': 3600.0, 'sample_second': 0.0},
                {'status': 'unknown', 'reason': 'clock_not_readable', 'sample_second': 7.0},
            ],
        ):
            result = transport_spot_check.verify_transport_spot_check(Mock(parent=Mock()), Mock(), 30)
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(result['reason'], 'mismatch_not_confirmed')

    def test_two_consistent_mismatches_block(self):
        with patch.object(
            transport_spot_check,
            '_sample',
            side_effect=[
                {'status': 'mismatch', 'offset_seconds': 3600.0, 'sample_second': 0.0},
                {'status': 'mismatch', 'offset_seconds': 3601.0, 'sample_second': 7.0},
            ],
        ):
            result = transport_spot_check.verify_transport_spot_check(Mock(parent=Mock()), Mock(), 30)
        self.assertEqual(result['status'], 'mismatch')
        self.assertEqual(result['reason'], 'confirmed_osd_clock_mismatch')


class TransportClockPromotionTests(unittest.TestCase):
    def _agent(self, result):
        verifier = Mock(return_value=dict(result))
        return types.SimpleNamespace(verify_clip_time=verifier), verifier

    def _client_class(self):
        class Client:
            def download_playback_stream(self, playback_uri, output_path, duration):
                return None
        return Client

    def _verified_attestation(self):
        return {
            'verified': True,
            'reason': 'absolute_clock_range_match',
            'describe_accepted': True,
            'play_accepted': True,
            'range_kind': 'clock',
            'range_end_present': True,
            'start_delta_seconds': 0.0,
            'end_delta_seconds': 0.0,
            'requested_duration_seconds': 30.0,
            'sdp_corrected': True,
            'relay_failed': False,
        }

    def _relay_teardown_attestation(self):
        att = self._verified_attestation()
        att.update(
            verified=False,
            reason='relay_failed',
            relay_failed=True,
            download_succeeded=True,
        )
        return att

    def _run(self, attestation, spot):
        agent, original = self._agent({'status': 'unknown', 'reason': 'insufficient_clock_readings'})
        Client = self._client_class()
        transport_clock.install(agent, Client, Mock())
        hik = Client()
        hik._playback_codec_relay_used = True
        hik._playback_timing_attestation = dict(attestation)
        with patch.object(transport_clock, 'verify_transport_spot_check', return_value=dict(spot)):
            result = agent.verify_clip_time(hik, 10, Mock(), Mock(), 30)
        return result, original

    def test_strict_transport_unknown_spot_uses_fast_path_without_full_ocr(self):
        result, original = self._run(
            self._verified_attestation(),
            {'status': 'unknown', 'method': 'osd_transport_spot_check', 'reason': 'clock_not_readable'},
        )
        self.assertEqual(result['status'], 'matched')
        self.assertEqual(result['method'], 'rtsp_play_absolute_clock')
        self.assertTrue(result['transport_fast_path'])
        original.assert_not_called()

    def test_successful_download_tolerates_only_post_play_relay_teardown(self):
        result, original = self._run(
            self._relay_teardown_attestation(),
            {'status': 'unknown', 'method': 'osd_transport_spot_check', 'reason': 'clock_not_readable'},
        )
        self.assertEqual(result['status'], 'matched')
        self.assertEqual(
            result['reason'],
            'upstream_play_clock_range_matched_after_successful_download',
        )
        original.assert_not_called()

    def test_confirmed_spot_mismatch_is_never_overridden(self):
        result, original = self._run(
            self._relay_teardown_attestation(),
            {
                'status': 'mismatch',
                'method': 'osd_transport_spot_check',
                'reason': 'confirmed_osd_clock_mismatch',
                'offset_seconds': 3600.0,
            },
        )
        self.assertEqual(result['status'], 'mismatch')
        original.assert_not_called()

    def test_incomplete_transport_proof_falls_back_to_full_ocr(self):
        mutations = (
            {'download_succeeded': False},
            {'play_accepted': False},
            {'range_kind': 'npt'},
            {'start_delta_seconds': 2.0},
            {'end_delta_seconds': -2.0},
            {'sdp_corrected': False},
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                att = self._relay_teardown_attestation()
                att.update(mutation)
                agent, original = self._agent({'status': 'unknown', 'reason': 'insufficient_clock_readings'})
                Client = self._client_class()
                transport_clock.install(agent, Client, Mock())
                hik = Client()
                hik._playback_codec_relay_used = True
                hik._playback_timing_attestation = att
                result = agent.verify_clip_time(hik, 10, Mock(), Mock(), 30)
                self.assertEqual(result['status'], 'unknown')
                original.assert_called_once()

    def test_full_ocr_mismatch_still_wins_without_strict_transport_proof(self):
        att = self._verified_attestation()
        att['requested_duration_seconds'] = 29.0
        agent, original = self._agent({'status': 'mismatch', 'reason': 'offset'})
        Client = self._client_class()
        transport_clock.install(agent, Client, Mock())
        hik = Client()
        hik._playback_codec_relay_used = True
        hik._playback_timing_attestation = att
        result = agent.verify_clip_time(hik, 10, Mock(), Mock(), 30)
        self.assertEqual(result['status'], 'mismatch')
        original.assert_called_once()


if __name__ == '__main__':
    unittest.main()
