import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'token_storage.dart';
import 'user_model.dart';

/// طبقة التواصل مع /api/auth/* — منفصلة عن إدارة الحالة (AuthState)
/// حتى يسهل اختبارها أو استبدالها لاحقاً
class AuthRepository {
  AuthRepository(this._client);
  final ApiClient _client;

  /// تسجيل الدخول: يحفظ التوكنات ثم يجلب بيانات المستخدم
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.raw.post(
        ApiEndpoints.login,
        data: {'username': username, 'password': password},
      );
      await TokenStorage.instance.saveTokens(
        accessToken: response.data['access'] as String,
        refreshToken: response.data['refresh'] as String,
      );
      return fetchCurrentUser();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// جلب بيانات المستخدم الحالي عبر /api/auth/me/
  Future<UserModel> fetchCurrentUser() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.me);
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// تسجيل مستخدم جديد (مريض أو طبيب فقط — الـ backend يمنع engineer عبر التسجيل العام)
  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String role, // 'patient' or 'doctor'
    String? phoneNumber,
    String? specialty,
  }) async {
    try {
      await _client.raw.post(
        ApiEndpoints.register,
        data: {
          'username': username,
          'email': email,
          'password': password,
          'role': role,
          if (phoneNumber != null) 'phone_number': phoneNumber,
          if (specialty != null) 'specialty': specialty,
        },
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// يُبطل الـ refresh token في الخادم (blacklist) ثم يمسح التوكنات محلياً.
  /// Dio مستقل بلا interceptor: لا نريد محاولة تجديد إن رُفض الطلب، ولا
  /// نؤخّر الخروج أكثر من 5 ثوانٍ. بلا شبكة يُمسح محلياً فقط ويبقى الـ
  /// refresh صالحاً في الخادم إلى أن تنتهي مدته.
  Future<void> logout() async {
    final refreshToken = await TokenStorage.instance.refreshToken;
    if (refreshToken != null) {
      try {
        await Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        )).post(ApiEndpoints.logout, data: {'refresh': refreshToken});
      } catch (_) {
        // الخروج يكتمل محلياً على أي حال
      }
    }
    await TokenStorage.instance.clear();
  }
}
