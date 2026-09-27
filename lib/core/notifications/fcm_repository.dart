import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';

/// طبقة التواصل مع /api/fcm-token/ — تسجيل الفشل هنا بصمت دائماً، لأن
/// تسجيل الدخول أو تسجيل الخروج يجب ألا يتعطل بسبب مشكلة إشعارات.
class FcmRepository {
  FcmRepository(this._client);
  final ApiClient _client;

  Future<void> registerToken({
    required String token,
    required String platform,
  }) async {
    try {
      await _client.raw.post(
        ApiEndpoints.fcmToken,
        data: {'token': token, 'platform': platform},
      );
    } on DioException {
      // فشل تسجيل التوكن (مثلاً الشبكة غير متاحة) لا يمنع استخدام التطبيق
    }
  }

  Future<void> unregisterToken(String token) async {
    try {
      await _client.raw.delete(
        ApiEndpoints.fcmToken,
        data: {'token': token},
      );
    } on DioException {
      // المستخدم يسجّل خروج على أي حال؛ لا داعي لإفشال العملية
    }
  }
}
