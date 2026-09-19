'use strict';

const PORTAL_SCOPE = new URL('./', self.location.href).pathname;
const PORTAL_PATH = new URL('index.html', self.location.href).pathname;

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

function portalUrl(value) {
  try {
    const candidate = new URL(value || PORTAL_PATH, self.location.origin);
    if (
      candidate.origin === self.location.origin &&
      candidate.pathname.startsWith(PORTAL_SCOPE)
    ) {
      return `${candidate.pathname}${candidate.search}${candidate.hash}`;
    }
  } catch (_) {
    // Fall through to the safe, same-origin customer portal.
  }
  return PORTAL_PATH;
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {};
  }

  event.waitUntil(
    self.registration.showNotification(data.title || 'ZHIROX', {
      body: data.body || '',
      icon: './apple-touch-icon.png',
      badge: './apple-touch-icon.png',
      data: { url: portalUrl(data.url) },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = portalUrl(event.notification.data?.url);
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });

    if (windows.length > 0) {
      const customerPortal = windows[0];
      if ('navigate' in customerPortal) await customerPortal.navigate(target);
      await customerPortal.focus();
      return;
    }

    await self.clients.openWindow(target);
  })());
});
