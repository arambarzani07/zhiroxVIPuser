# ZHIROX iOS Ad Hoc Signing

This repository keeps the normal Owner/User CI pipeline unsigned and public. A separate manual workflow, `.github/workflows/ios-signed-adhoc.yml`, produces a signed Ad Hoc IPA as a short-lived private GitHub Actions artifact.

## App identities

- Owner bundle ID: `com.karoxghafoor.zhirox.owner`
- User bundle ID: `com.karoxghafoor.zhirox.user`
- Owner source: `owner-source`
- User source: `user-source`

The signing workflow validates the selected provisioning profile against the exact bundle ID and Apple Team ID before building.

## Apple Developer prerequisites

Use an active paid Apple Developer Program membership. In Apple Developer, create both App IDs above. Register every iPhone/iPad that must install the Ad Hoc build, then create one Ad Hoc Distribution provisioning profile for each App ID.

Export an `Apple Distribution` certificate together with its private key as a password-protected `.p12` file. Do not commit the certificate, private key, provisioning profiles, passwords, device UDIDs, or base64 values to this repository.

## Local preflight before adding secrets

On a Mac, validate the `.p12` and both Ad Hoc profiles before placing anything in GitHub Secrets:

```bash
P12_PASSWORD='your-p12-password' \
  ./scripts/ios_signing_preflight.sh \
  /path/to/distribution.p12 \
  /path/to/ZHIROX-Owner.mobileprovision \
  /path/to/ZHIROX-User.mobileprovision \
  YOUR_TEAM_ID
```

The preflight checks the Apple Distribution identity, Team ID, exact Owner/User bundle IDs, profile expiry, Ad Hoc device list, and `get-task-allow=false`. It does not print certificate/profile bytes or the P12 password.

## Required GitHub Actions secrets

Create these repository Actions secrets:

- `APPLE_TEAM_ID` — the Apple Developer Team ID.
- `APPLE_P12_BASE64` — base64 of the password-protected Apple Distribution `.p12`.
- `APPLE_P12_PASSWORD` — password used when exporting the `.p12`.
- `OWNER_MOBILEPROVISION_BASE64` — base64 of the Owner Ad Hoc provisioning profile.
- `USER_MOBILEPROVISION_BASE64` — base64 of the User Ad Hoc provisioning profile.

On macOS, encode a file without line wrapping with:

```bash
base64 -i distribution.p12 | tr -d '\n'
base64 -i ZHIROX-Owner.mobileprovision | tr -d '\n'
base64 -i ZHIROX-User.mobileprovision | tr -d '\n'
```

Store the resulting values only in GitHub Actions secrets.

## Run the signer

Open GitHub Actions, choose **iOS Signed Ad Hoc**, select **Run workflow**, then choose `owner` or `user`.

Before signing, the workflow verifies:

- all required secrets exist;
- the provisioning profile belongs to `APPLE_TEAM_ID`;
- the profile application identifier exactly matches the selected bundle ID;
- the profile is an Ad Hoc profile with registered devices;
- the profile has not expired;
- an Apple Distribution identity is present;
- the app passes the online-only verifier, `flutter analyze`, and `flutter test`;
- the exported IPA has a valid code signature and the expected embedded profile.

The result is uploaded for three days as a private Actions artifact:

- `zhirox-owner-signed-adhoc` containing `ZHIROX-Owner-Signed.ipa`, or
- `zhirox-user-signed-adhoc` containing `ZHIROX-User-Signed.ipa`.

The artifact also contains `ota-manifest-template.plist`.

## Safari / OTA installation

An Ad Hoc IPA can install only on devices included in its provisioning profile. For Safari OTA installation, host both the signed IPA and a completed manifest plist on a secure HTTPS origin. Replace the placeholder IPA URL in `ota-manifest-template.plist`, then open:

```text
itms-services://?action=download-manifest&url=https://YOUR-HTTPS-HOST/manifest.plist
```

Do not publish an Ad Hoc IPA from this public repository as a public GitHub Release. The embedded provisioning profile can disclose registered device identifiers. Use access-controlled HTTPS hosting for OTA distribution, or use TestFlight when public/private Apple-hosted distribution is preferable.

## Current validation boundary

CI can verify certificate/profile compatibility, signing, package structure, bundle identity, tests, and code-sign integrity. Final installation readiness is not complete until the signed IPA is installed and launched on a physical iPhone whose UDID is included in the Ad Hoc provisioning profile.
