import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تخزين آمن لتوكنات JWT (access + refresh)
/// flutter_secure_storage يدعم Android/iOS/macOS/Windows/Linux
///
/// الويب (PWA) مختلف: تخزين flutter_secure_storage هناك يضع مفتاح التشفير
/// في localStorage بجانب النص المشفّر، فأي script على الصفحة يقرؤهما. لذا
/// على الويب: access بالذاكرة فقط، والـ refresh في كوكي HttpOnly يديره
/// المتصفح والخادم (accounts/web_auth.py) ولا يراه Dart إطلاقاً.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  /// true على الويب: الـ refresh في كوكي، لا في هذا التخزين.
  static bool get usesRefreshCookie => debugUseRefreshCookie ?? kIsWeb;

  /// لاختبار مسار الويب على الـ VM (kIsWeb ثابت هناك)
  @visibleForTesting
  static bool? debugUseRefreshCookie;

  final _storage = const FlutterSecureStorage();
  String? _memoryAccessToken;

  static const _accessKey = 'axon_access_token';
  static const _refreshKey = 'axon_refresh_token';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    if (usesRefreshCookie) {
      _memoryAccessToken = accessToken;
      return;
    }
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<String?> get accessToken async =>
      usesRefreshCookie ? _memoryAccessToken : await _storage.read(key: _accessKey);

  /// دائماً null على الويب (الـ refresh في كوكي HttpOnly)
  Future<String?> get refreshToken async =>
      usesRefreshCookie ? null : await _storage.read(key: _refreshKey);

  Future<void> updateAccessToken(String accessToken) async {
    if (usesRefreshCookie) {
      _memoryAccessToken = accessToken;
      return;
    }
    await _storage.write(key: _accessKey, value: accessToken);
  }

  Future<void> clear() async {
    if (usesRefreshCookie) {
      _memoryAccessToken = null;
      return;
    }
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  /// على الويب: هل يوجد access بالذاكرة؟ بعد إعادة تحميل الصفحة يكون false
  /// حتى تستعيد AuthNotifier الجلسة بالكوكي (ApiClient.restoreWebSession).
  Future<bool> get hasTokens async => (await accessToken) != null;
}
