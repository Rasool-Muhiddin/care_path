import 'package:dio/dio.dart';

import '../auth/token_storage.dart';
import 'api_endpoints.dart';

/// استثناء موحّد لأخطاء الـ API — يسهّل عرض رسائل واضحة في الواجهة
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Callback يُستدعى عند فشل تجديد التوكن (يعني الجلسة انتهت فعلياً)
/// يُستخدم من AuthState لتسجيل الخروج تلقائياً وإعادة التوجيه لشاشة الدخول
typedef OnSessionExpired = void Function();

class ApiClient {
  ApiClient({required this.onSessionExpired}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.api,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  late final Dio _dio;
  final OnSessionExpired onSessionExpired;

  Dio get raw => _dio;

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.instance.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // عند انتهاء صلاحية access token: نحاول تجديده مرة واحدة فقط
        final isUnauthorized = error.response?.statusCode == 401;
        final isRetry = error.requestOptions.extra['retried'] == true;

        if (isUnauthorized && !isRetry) {
          final refreshed = await _tryRefreshToken();
          if (refreshed) {
            final opts = error.requestOptions;
            opts.extra['retried'] = true;
            final newToken = await TokenStorage.instance.accessToken;
            opts.headers['Authorization'] = 'Bearer $newToken';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(error);
            }
          } else {
            await TokenStorage.instance.clear();
            onSessionExpired();
          }
        }
        handler.next(error);
      },
    );
  }

  Future<bool> _tryRefreshToken() async {
    final refreshToken = await TokenStorage.instance.refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await Dio().post(
        ApiEndpoints.refresh,
        data: {'refresh': refreshToken},
      );
      final newAccess = response.data['access'] as String;
      await TokenStorage.instance.updateAccessToken(newAccess);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يحوّل استثناءات Dio إلى ApiException برسالة عربية واضحة
  ApiException mapError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException('انتهت مهلة الاتصال بالخادم، حاول مرة أخرى');
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException('تعذّر الاتصال بالخادم، تحقق من الاتصال بالإنترنت');
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String message = 'حدث خطأ غير متوقع';
    if (data is Map && data.isNotEmpty) {
      final first = data.values.first;
      message = first is List ? first.join(', ') : first.toString();
    }
    return ApiException(message, statusCode: status);
  }
}
