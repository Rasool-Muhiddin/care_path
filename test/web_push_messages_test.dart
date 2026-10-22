import 'package:axon/core/notifications/web_push.dart';
import 'package:flutter_test/flutter_test.dart';

/// العقد بين web/firebase-messaging-sw.js والتطبيق (نفس أسماء الحقول).
void main() {
  test('push and click messages from the service worker', () {
    final push = parseWebPushMessage({'axon': 'push', 'type': 'chat_message', 'case_id': '12'})!;
    expect(push.clicked, isFalse);
    expect(push.type, 'chat_message');
    expect(push.caseId, 12);

    final click = parseWebPushMessage({'axon': 'click', 'type': 'attack_reminder', 'case_id': ''})!;
    expect(click.clicked, isTrue);
    expect(click.caseId, isNull);
  });

  test('unrelated service worker messages are ignored', () {
    expect(parseWebPushMessage({'type': 'chat_message'}), isNull);
    expect(parseWebPushMessage('hello'), isNull);
    expect(parseWebPushMessage(null), isNull);
  });

  test('launch URL opened by a notification tap', () {
    final event = webPushEventFromLaunchUrl(Uri.parse('https://axon.example/app/?notification_type=chat_message&case=7#/'))!;
    expect(event.clicked, isTrue);
    expect(event.type, 'chat_message');
    expect(event.caseId, 7);
    expect(webPushEventFromLaunchUrl(Uri.parse('https://axon.example/app/#/patient')), isNull);
  });

  test('push is unsupported outside the browser', () {
    expect(webPushPermission(), WebPushPermission.unsupported);
  });
}
