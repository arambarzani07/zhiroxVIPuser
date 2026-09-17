'use strict';

const token = new URL(window.location.href).searchParams.get('token') || '';
const validToken = /^[a-f0-9]{64}$/.test(token);
const manifestHref = validToken
  ? `/functions/v1/customer-push-manifest?token=${encodeURIComponent(token)}`
  : '/functions/v1/customer-push-manifest';

document.write(
  `<link id="appManifest" rel="manifest" href="${manifestHref}">`,
);
