# ZHIROX Hikvision Transaction Video Gateway

This gateway links ZHIROX financial transactions to recorded Hikvision video without exposing the NVR to the Internet.

## Security model

- NVR stays on the market LAN (`192.168.1.2` for Kani Chnar).
- No router port-forwarding is required.
- NVR username/password never leave the Windows gateway computer.
- NVR password and the ZHIROX gateway token are encrypted at rest with Windows DPAPI for the current Windows user.
- The cloud stores only the SHA-256 hash of the gateway token.
- The gateway makes outbound HTTPS requests only.
- Video is uploaded to the private Supabase bucket `transaction-camera-clips`.

## Kani Chnar defaults

- Model: `DS-7616NI-K2/16P`
- NVR host: `192.168.1.2`
- Cashier camera channel: `1`
- Evidence window: 15 seconds before + 30 seconds after the transaction
- Timezone: `Asia/Baghdad`

## Install

1. In ZHIROX Admin > Settings > Hikvision, generate a new gateway token. It is shown only once.
2. Download the `zhirox-hikvision-gateway-windows` artifact.
3. Keep both EXEs in the same folder.
4. Run `zhirox-hikvision-setup.exe` on the always-on cashier Windows PC.
5. Enter the NVR username/password locally and paste the one-time gateway token.
6. Setup verifies `/ISAPI/System/deviceInfo`, verifies the cloud token, encrypts both secrets with DPAPI, and can install an auto-start task.
7. Run `zhirox-hikvision-gateway.exe` (or sign out/in if auto-start was installed).

## Runtime flow

1. A new debt/payment is inserted in ZHIROX.
2. PostgreSQL creates a private video job containing only transaction time, channel and clip window.
3. The local gateway claims the job over HTTPS.
4. It searches recordings with `POST /ISAPI/ContentMgmt/search` using HTTP Digest authentication.
5. It downloads the matching recording through `/ISAPI/ContentMgmt/download`.
6. FFmpeg is required. The gateway seeks to the requested window and encodes an H.264 Main / yuv420p MP4 (up to 1920×1080, 25 fps), with AAC audio when present and faststart metadata. It fully decodes the output before upload. Missing FFmpeg, empty video or conversion failure reports a failed job; an unverified raw recording is never uploaded as Ready. Actual video duration and encoding are saved in playback metadata.
7. The clip is uploaded with a short-lived signed upload URL and SHA-256 is stored with the evidence record.
8. Temporary local video is deleted.

Gateway log: `%LOCALAPPDATA%\ZHIROX\HikvisionGateway\gateway.log`.
Encrypted config: `%LOCALAPPDATA%\ZHIROX\HikvisionGateway\config.json`.

## Recorder preflight (before enabling automatic capture)

Run `zhirox-hikvision-diagnose.exe` in a Windows terminal **on the market LAN**.
The password is requested privately in the terminal, used in memory, and not saved.
No gateway token is needed. Diagnostics do not alter NVR settings or platform access,
and do not contact ZHIROX cloud or claim jobs. Search uses the recorder's search API;
it does not change recordings.

```powershell
.\zhirox-hikvision-diagnose.exe --host 192.168.1.2 --channel 1
```

The default checks a moment two minutes ago to allow recordings to become available.
The IP and cashier channel are examples; confirm them at the market.
`nvr_access: ok` verifies authenticated ISAPI device information.
`clock_status: ok` indicates the recorder clock is within 60 seconds of the PC clock.
`found_at_requested_time` verifies that the returned segment contains the selected
instant. `requested_window_covered` separately checks the full 15-second-before /
30-second-after window. A neighboring segment is not accepted as evidence.

To test the download at a known recorded local time (Baghdad offset `+03:00`):

```powershell
.\zhirox-hikvision-diagnose.exe --host 192.168.1.2 --channel 1 --at "2026-10-03T17:00:00+03:00" --download "$env:USERPROFILE\Desktop\zhirox-nvr-test.mp4"
```

Replace the sample timestamp with one you can verify in Playback.
The download is a matching **NVR segment**, not yet an exactly trimmed 45-second clip.
Open it in a video player and compare the camera and displayed time. A nonempty
file/hash alone does not prove the video is playable or the NVR clock is correct.
Existing files are never overwritten; failed partial downloads are removed.
No diagnostic video is uploaded. Treat local recordings as private.

If access returns HTTP 401/403, verify the local recorder account and playback
permissions. If there is no response, confirm the actual LAN IP, HTTP(S) port, and
that the PC is on the same reachable network. `not_found` means the selected
channel/time has no matching search result; check Playback and recording schedule.
Do not change Hik-Connect/Platform Access to run this test.

After playback and time checks succeed, use the setup wizard with the one-time
ZHIROX gateway token, enable the **Local Gateway** provider in ZHIROX, and create
one genuine test transaction. Verify the job, uploaded clip, transaction link,
and that Hik-Connect still works before leaving automatic capture enabled.

Auto-start is **at this Windows user's logon**, not before anyone signs in after
power restoration. Keep the same Windows user (DPAPI keys belong to that user),
network access, and the PC awake. This is not an unattended Windows service.

## Playback compatibility update — 2026-10-04

Previously the gateway used stream copy, which retained recorder HEVC/hev1 video even in an MP4 file. This update transcodes and validates new clips. It does not change existing uploaded clips or recorder settings, and does not verify the camera OSD timestamp against transaction time. Keep the existing encrypted config and FFmpeg; replace only the gateway executable and restart it once under the same Windows user. FFmpeg can be on PATH, beside the executable, or in the encrypted-config directory.

## Time-window download update — 2026-10-04

The previous downloader sent an XML body in a GET request, whereas Hikvision documents POST-with-XML or GET-with-playbackURI-query. New downloads use POST-with-XML (GET-query fallback only for unsupported POST). Transaction jobs rebuild the playback URI with the requested UTC start/end and remove file-name/size selectors so download-by-file cannot select an earlier file start. Search results must cover the requested window; nearest results are rejected. Conversion starts at the explicit download start, not the search segment start. Logs and playback metadata include the time-window request and build marker, but never recorder credentials or signed cloud URLs.

This fixes request construction defects. It does not establish that a particular recorder honors UTC or the requested media boundaries. Compare a known transaction with NVR Playback after installing before treating a clip as correctly timed evidence. No fixed four-hour adjustment is applied. Existing uploaded clips are not rewritten. Keep config, FFmpeg, recorder clock and PC clock unchanged.


## Gateway 1.2.0+osd-1: displayed-clock warnings

Uses bundled Tesseract OCR locally; no Windows language-pack installation is needed. A live snapshot and `/ISAPI/System/time`
resolve the recorder offset and date order; three rendered clip samples are
compared with the requested start. At least two distinct readings must progress
with playback and agree within two seconds. A five-second tolerance allows
whole-second OSD and frame sampling. Results are `matched`, `mismatch`, or
`unknown`; none adjusts the recorder clock or automatically shifts requests.
Unavailable OCR, unavailable snapshot, hidden OSD, ambiguous date order,
OCR errors and unsupported formats report unknown and do not stop uploading.
Only extracted timestamps and result metadata leave the PC; temporary snapshots
and crops are removed. Old clips have no OCR result until explicitly rebuilt.

Install by stopping the old gateway, replacing `zhirox-hikvision-gateway.exe`
at the existing installed path, then starting it once. Keep config.json and
FFmpeg. No new token or setup is required. The app permits manual rebuilds only
while a recent 1.2-or-newer gateway is active. Rebuilds preserve old storage files
and a private evidence snapshot, fence old callbacks, and do not modify debts.

## Gateway 1.2.1+download-compat-1

Retries download rejection HTTP 400/405/422/501 using GET with the same XML request body, as specified by the ISAPI General Application Developer Guide section 15.2.2. Channel and transaction time bounds stay unchanged; file-name selectors are never restored. Device rejection status fields are recorded without including credentials or playback URLs. This is a compatibility fix; correct footage still requires a recorder test and timestamp comparison.
