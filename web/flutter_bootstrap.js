{{flutter_js}}
{{flutter_build_config}}

// Axon: CanvasKit from our own server (build/web/canvaskit/, served under
// /app/), not www.gstatic.com — one less third-party dependency, works when
// gstatic is slow or blocked, and keeps the Content-Security-Policy tight.
// No serviceWorkerSettings: Flutter's own service worker is deprecated and not
// used; push uses /firebase-messaging-sw.js (web/firebase-messaging-sw.js).
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
