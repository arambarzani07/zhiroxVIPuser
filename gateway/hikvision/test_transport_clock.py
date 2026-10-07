import types
import unittest
from unittest.mock import Mock

from rtsp_codec_relay import SdpCodecRelay
import transport_clock


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
        relay._request(
            f'DESCRIBE {local} RTSP/1.0\r\nCSeq: 1\r\n\r\n'.encode()
        )
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
        relay._request(
            f'PLAY {local} RTSP/1.0\r\nCSeq: 2\r\n\r\n'.encode()
        )
        header = b'RTSP/1.0 200 OK\r\nCSeq: 2\r\n'
        if range_value is not None:
            header += f'Range: {range_value}\r\n'.encode()
        relay._response(header + b'\r\n')

    def test_absolute_play_clock_match_is_verified(self):
        relay = self._relay()
        self._accept_describe_with_correction(relay)
        self._play(
            relay,
            'clock=20261007T065519Z-20261007T065549Z',
        )
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


class TransportClockPromotionTests(unittest.TestCase):
    def _agent(self, result):
        return types.SimpleNamespace(
            verify_clip_time=lambda *args, **kwargs: dict(result)
        )

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

    def test_unknown_clock_promotes_only_with_full_transport_proof(self):
        agent = self._agent({'status': 'unknown', 'reason': 'insufficient_clock_readings'})
        Client = self._client_class()
        transport_clock.install(agent, Client, Mock())
        hik = Client()
        hik._playback_codec_relay_used = True
        hik._playback_timing_attestation = self._verified_attestation()
        result = agent.verify_clip_time(hik, 10, None, None, 30)
        self.assertEqual(result['status'], 'matched')
        self.assertEqual(result['method'], 'rtsp_play_absolute_clock')

    def test_real_mismatch_is_never_overridden(self):
        agent = self._agent({'status': 'mismatch', 'reason': 'offset'})
        Client = self._client_class()
        transport_clock.install(agent, Client, Mock())
        hik = Client()
        hik._playback_codec_relay_used = True
        hik._playback_timing_attestation = self._verified_attestation()
        self.assertEqual(
            agent.verify_clip_time(hik, 10, None, None, 30)['status'],
            'mismatch',
        )

    def test_duration_or_unverified_transport_cannot_promote(self):
        for mutation in (
            {'requested_duration_seconds': 29.0},
            {'verified': False, 'reason': 'range_not_absolute_clock'},
            {'range_kind': 'npt'},
        ):
            with self.subTest(mutation=mutation):
                agent = self._agent({'status': 'unknown', 'reason': 'insufficient_clock_readings'})
                Client = self._client_class()
                transport_clock.install(agent, Client, Mock())
                hik = Client()
                hik._playback_codec_relay_used = True
                att = self._verified_attestation()
                att.update(mutation)
                hik._playback_timing_attestation = att
                result = agent.verify_clip_time(hik, 10, None, None, 30)
                self.assertEqual(result['status'], 'unknown')
                self.assertIn('transport_', result['reason'])


if __name__ == '__main__':
    unittest.main()
