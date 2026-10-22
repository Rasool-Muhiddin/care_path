import 'package:firebase_core/firebase_core.dart';

/// إعداد Firebase لتطبيق الويب (Firebase Console → Project settings → Your
/// apps → Web app). قيم عامة وليست أسراراً، تُمرَّر وقت البناء:
///
///   flutter build web --dart-define-from-file=web_firebase.json ...
///
/// (القالب: web_firebase.example.json). بلا هذه القيم تعمل نسخة الويب كاملة
/// بلا إشعارات فقط. أندرويد/iOS يقرآن google-services.json / plist كما كانا.
class FirebaseWebConfig {
  FirebaseWebConfig._();

  static const _apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// المفتاح العام من Cloud Messaging → Web Push certificates
  static const vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  static bool get isConfigured =>
      _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty && vapidKey.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
      );
}
