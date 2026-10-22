import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_push_io.dart' show WebPushEvent, WebPushPermission, parseWebPushMessage, webPushEventFromLaunchUrl;

export 'web_push_io.dart' show WebPushEvent, WebPushPermission, parseWebPushMessage, webPushEventFromLaunchUrl;

/// iOS: Notification و PushManager موجودان فقط في تطبيق مُضاف للشاشة
/// الرئيسية (iOS 16.4+)؛ في تبويب Safari العادي لا يوجدان.
bool get _supported =>
    web.window.has('Notification') &&
    web.window.has('PushManager') &&
    web.window.navigator.has('serviceWorker');

WebPushPermission _fromJs(String value) => switch (value) {
      'granted' => WebPushPermission.granted,
      'denied' => WebPushPermission.denied,
      _ => WebPushPermission.notAsked,
    };

WebPushPermission webPushPermission() =>
    _supported ? _fromJs(web.Notification.permission) : WebPushPermission.unsupported;

/// يجب أن يُستدعى مباشرة من لمسة المستخدم (زر "تفعيل الإشعارات"): Safari
/// يرفض طلب الإذن من خارج لمسة. الطلب نفسه يحدث متزامناً قبل أي انتظار.
Future<WebPushPermission> requestWebPushPermission() async {
  if (!_supported) return WebPushPermission.unsupported;
  final result = await web.Notification.requestPermission().toDart;
  return _fromJs(result.toDart);
}

Stream<WebPushEvent> webPushEvents() {
  if (!web.window.navigator.has('serviceWorker')) return const Stream.empty();
  return web.EventStreamProviders.messageEvent
      .forTarget(web.window.navigator.serviceWorker)
      .map((event) => parseWebPushMessage(event.data.dartify()))
      .where((event) => event != null)
      .cast<WebPushEvent>();
}

WebPushEvent? initialWebPushEvent() => webPushEventFromLaunchUrl(Uri.base);
