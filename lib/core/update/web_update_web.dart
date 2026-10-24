import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// يطلب من المتصفح فحص كل service worker مسجَّل (حالياً
/// /firebase-messaging-sw.js) — النسخة الجديدة تُثبَّت وتتفعّل فوراً
/// (skipWaiting + clients.claim فيها) — ثم يعيد تحميل الصفحة. nginx يرسل
/// index.html وmain.dart.js بـ no-cache، فإعادة التحميل تجلب النسخة الجديدة.
/// iOS (التطبيق المثبَّت على الشاشة الرئيسية) لا يعيد تحميل الصفحة وحده
/// عند الرجوع إليه، ولهذا الزر.
Future<void> reloadToNewWebVersion() async {
  try {
    final container = web.window.navigator.serviceWorker;
    final registrations = (await container.getRegistrations().toDart).toDart;
    await Future.wait([
      for (final registration in registrations)
        registration.update().toDart.then<void>((_) {}, onError: (_) {}),
    ]).timeout(const Duration(seconds: 3), onTimeout: () => []);
  } catch (_) {
    // بلا دعم service worker (أو خطأ شبكة): إعادة التحميل تكفي للتطبيق نفسه
  }
  web.window.location.reload();
}
