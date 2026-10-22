// Axon — Web Push service worker (FCM).
//
// The Firebase JS SDK (FirebaseMessaging.getToken on web) always registers
// this file from the domain ROOT: /firebase-messaging-sw.js, scope
// /firebase-cloud-messaging-push-scope. nginx serves it there from build/web
// (deploy/nginx-axon.conf). The app itself lives under /app/.
//
// It deliberately does not load the Firebase SDK: FCM delivers a standard Web
// Push whose JSON payload carries `notification` and `data`, and we display it
// ourselves. Every push MUST show a notification — iOS Safari revokes the
// subscription of a web app that receives pushes silently.
'use strict';

const APP_URL = '/app/';
const DEFAULT_ICON = '/app/icons/Icon-192.png';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

function readPayload(event) {
  if (!event.data) return {};
  try {
    return event.data.json() || {};
  } catch (e) {
    return { notification: { body: event.data.text() } };
  }
}

async function appWindows() {
  const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  return all.filter((client) => new URL(client.url).pathname.startsWith(APP_URL));
}

self.addEventListener('push', (event) => {
  const payload = readPayload(event);
  const notification = payload.notification || {};
  const data = payload.data || {};
  const caseId = data.case_id || '';

  event.waitUntil((async () => {
    // Open app windows refresh the chat / unread badge right away.
    for (const client of await appWindows()) {
      client.postMessage({ axon: 'push', type: data.type || '', case_id: caseId });
    }
    await self.registration.showNotification(notification.title || 'Axon', {
      body: notification.body || '',
      icon: notification.icon || DEFAULT_ICON,
      badge: DEFAULT_ICON,
      lang: 'ar',
      dir: 'rtl',
      // One notification per conversation instead of a stack.
      tag: caseId ? `case-${caseId}` : (data.type || 'axon'),
      data: { type: data.type || '', case_id: caseId },
    });
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const message = { axon: 'click', type: data.type || '', case_id: data.case_id || '' };

  event.waitUntil((async () => {
    const windows = await appWindows();
    if (windows.length > 0) {
      const client = windows[0];
      await client.focus();
      client.postMessage(message);
      return;
    }
    // App closed: it reads ?notification_type/&case from its URL on start.
    const params = new URLSearchParams();
    if (message.type) params.set('notification_type', message.type);
    if (message.case_id) params.set('case', message.case_id);
    const query = params.toString();
    await self.clients.openWindow(APP_URL + (query ? `?${query}` : ''));
  })());
});
