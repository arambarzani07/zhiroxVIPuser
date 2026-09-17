'use strict';

const currentUrl = new URL(window.location.href);
const queryToken = currentUrl.searchParams.get('token') || '';
const fragmentToken = new URLSearchParams(
  currentUrl.hash.startsWith('#') ? currentUrl.hash.slice(1) : currentUrl.hash,
).get('token') || '';
const token = queryToken || fragmentToken;
const validToken = /^[a-f0-9]{64}$/.test(token);
const manifestHref = validToken
  ? `https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-manifest?token=${encodeURIComponent(token)}`
  : './manifest.webmanifest';

document.write(
  `<link id="appManifest" rel="manifest" crossorigin="anonymous" href="${manifestHref}">`,
);
