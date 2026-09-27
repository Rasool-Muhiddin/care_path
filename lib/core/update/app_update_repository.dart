import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'app_version_model.dart';

/// طبقة التواصل مع /api/app-version/latest/ — منفصلة عن منطق المقارنة
/// (AppUpdateProvider) حتى يسهل اختبارها.
class AppUpdateRepository {
  AppUpdateRepository(this._client);
  final ApiClient _client;

  /// يرجع آخر نسخة منشورة لهذه المنصة، أو null إذا لم يُنشر أي إصدار بعد
  /// (404) أو تعذّر الوصول للخادم. فشل الفحص لا يجب أبداً أن يمنع
  /// المستخدم من استخدام التطبيق.
  Future<AppVersionInfo?> fetchLatest({required String platform}) async {
    try {
      final response = await _client.raw.get(
        ApiEndpoints.appVersionLatest,
        queryParameters: {'platform': platform},
      );
      return AppVersionInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      return null;
    }
  }
}
