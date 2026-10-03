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
6. If `ffmpeg.exe` is available on PATH (or beside the gateway config), the segment is losslessly trimmed to the requested window; otherwise the matching Hikvision recording segment is retained and the requested timestamps are saved as metadata.
7. The clip is uploaded with a short-lived signed upload URL and SHA-256 is stored with the evidence record.
8. Temporary local video is deleted.

Gateway log: `%LOCALAPPDATA%\ZHIROX\HikvisionGateway\gateway.log`.
Encrypted config: `%LOCALAPPDATA%\ZHIROX\HikvisionGateway\config.json`.
