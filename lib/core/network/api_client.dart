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

  /// تجديد واحد فقط في أي لحظة: إذا انتهى الـ token وفشلت عدة طلبات معاً
  /// (مثلاً جلسات + تقارير نوبات عند فتح شاشة)، تنتظر كلها نفس عملية التجديد
  /// بدل أن يبدأ كل طلب تجديداً خاصاً به ويتسابقون على الكتابة في التخزين.
  Future<String?>? _refreshing;

  Future<String?> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        // الطلب المُعاد بعد التجديد يحمل التوكن الجديد أصلاً؛ لا نقرأ التخزين
        // مرة ثانية كي لا نرجع بالخطأ إلى توكن قديم.
        if (options.extra['retried'] != true) {
          final token = await TokenStorage.instance.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // عند انتهاء صلاحية access token: نحاول تجديده مرة واحدة فقط
        final isUnauthorized = error.response?.statusCode == 401;
        final isRetry = error.requestOptions.extra['retried'] == true;

        if (isUnauthorized && !isRetry) {
          final newToken = await _refreshAccessToken();
          if (newToken != null) {
            final opts = error.requestOptions;
            opts.extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer $newToken';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } on DioException catch (retryError) {
              // نُرجع الخطأ الحقيقي للطلب المُعاد (مثلاً 403) وليس الـ 401 الأصلي.
              return handler.next(retryError);
            }
          }
        }
        handler.next(error);
      },
    );
  }

  /// يجدد الـ access token. يرجع التوكن الجديد، أو null عند الفشل.
  /// نعتبر الجلسة منتهية (تسجيل خروج) فقط إذا رفض الخادم الـ refresh token
  /// نفسه؛ أما انقطاع الشبكة أو تعطل الخادم فلا يسجّل خروج المستخدم.
  Future<String?> _doRefresh() async {
    final refreshToken = await TokenStorage.instance.refreshToken;
    if (refreshToken == null) {
      await TokenStorage.instance.clear();
      onSessionExpired();
      return null;
    }
    try {
      final response = await Dio().post(
        ApiEndpoints.refresh,
        data: {'refresh': refreshToken},
      );
      final newAccess = response.data['access'] as String;
      // إن فعّلت ROTATE_REFRESH_TOKENS يرجع الخادم refresh جديداً أيضاً.
      final newRefresh = response.data['refresh'] as String?;
      if (newRefresh != null) {
        await TokenStorage.instance.saveTokens(
          accessToken: newAccess,
          refreshToken: newRefresh,
        );
      } else {
        await TokenStorage.instance.updateAccessToken(newAccess);
      }
      return newAccess;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        await TokenStorage.instance.clear();
        onSessionExpired();
      }
      return null;
    } catch (_) {
      return null;
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