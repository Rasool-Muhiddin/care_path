// إشعارات الويب (PWA): إذن المتصفح، ورسائل الـ service worker
// (web/firebase-messaging-sw.js). على أندرويد/iOS: بلا عمل (FCM الأصلي).
export 'web_push_io.dart' if (dart.library.js_interop) 'web_push_web.dart';
