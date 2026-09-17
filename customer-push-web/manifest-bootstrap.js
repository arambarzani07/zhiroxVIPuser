'use strict';

// This script intentionally blocks HTML parsing so Safari sees the
// token-aware manifest before Add to Home Screen reads installation metadata.
const token = new URL(window.location.href).searchParams.get('token') || '';
const validToken = /^[a-f0-9]{64}$/.test(token);
const manifestHref = validToken
  ? `/install-manifest.webmanifest?token=${encodeURIComponent(token)}`
  : '/manifest.webmanifest';

document.write(
  `<link id="appManifest" rel="manifest" href="${manifestHref}">`,
);
