/// إذن إشعارات المتصفح كما يراه التطبيق
enum WebPushPermission { unsupported, notAsked, granted, denied }

/// رسالة من الـ service worker: [clicked] = ضغط على الإشعار، وإلا وصل push
/// والتطبيق مفتوح. [caseId] للمحادثة إن وُجدت.
class WebPushEvent {
  const WebPushEvent({required this.clicked, required this.type, this.caseId});
  final bool clicked;
  final String type;
  final int? caseId;
}

WebPushPermission webPushPermission() => WebPushPermission.unsupported;

Future<WebPushPermission> requestWebPushPermission() async => WebPushPermission.unsupported;

Stream<WebPushEvent> webPushEvents() => const Stream.empty();

/// الإشعار الذي فتح التطبيق وهو مغلق (من رابط الـ service worker)
WebPushEvent? initialWebPushEvent() => null;

/// رسالة من web/firebase-messaging-sw.js: {axon: push|click, type, case_id}
WebPushEvent? parseWebPushMessage(Object? data) {
  if (data is! Map) return null;
  final kind = data['axon'];
  if (kind != 'push' && kind != 'click') return null;
  return WebPushEvent(
    clicked: kind == 'click',
    type: '${data['type'] ?? ''}',
    caseId: int.tryParse('${data['case_id'] ?? ''}'),
  );
}

/// /app/?notification_type=chat_message&case=12 — يفتحه الـ service worker
/// عند الضغط على إشعار والتطبيق مغلق
WebPushEvent? webPushEventFromLaunchUrl(Uri url) {
  final type = url.queryParameters['notification_type'];
  if (type == null) return null;
  return WebPushEvent(clicked: true, type: type, caseId: int.tryParse(url.queryParameters['case'] ?? ''));
}
