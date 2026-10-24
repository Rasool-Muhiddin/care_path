// تحديث نسخة الويب (PWA): تفعيل الـ service worker الجديد وإعادة تحميل
// الصفحة. على أندرويد/iOS: بلا عمل (التحديث هناك عبر APK).
export 'web_update_io.dart' if (dart.library.js_interop) 'web_update_web.dart';
