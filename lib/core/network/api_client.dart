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
        headers: _clientHeaders,
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  late final Dio _dio;
  final OnSessionExpired onSessionExpired;

  Dio get raw => _dio;

  /// نسخة الويب تُعرّف نفسها للخادم فيضع الـ refresh في كوكي HttpOnly
  /// (accounts/web_auth.py). التطبيقات لا ترسله فيبقى الـ refresh في الجسم.
  static Map<String, String> get _clientHeaders =>
      TokenStorage.usesRefreshCookie ? const {'X-Axon-Client': 'web'} : const {};

  /// Dio بلا interceptor لطلبات التجديد والخروج: لا محاولة تجديد إن رُفض
  /// الطلب نفسه. يشارك الـ adapter مع [raw] (وفي الاختبارات adapter وهمياً).
  Dio bareDio({Duration? timeout}) => Dio(BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        headers: _clientHeaders,
      ))
        ..httpClientAdapter = _dio.httpClientAdapter;

  /// أكبر صفحة يقبلها الخادم (config.drf.DefaultPagination.max_page_size)
  static const maxPageSize = 200;

  /// يجلب كل عناصر قائمة مرقّمة: يطلب الصفحات بالترتيب (?page=1,2,...)
  /// إلى أن يصبح "next" فارغاً. نبني رقم الصفحة بأنفسنا بدل اتباع رابط
  /// "next" المطلق، لأن الخادم خلف proxy قد يكتبه بـ http بدل https.
  /// يقبل أيضاً endpoint غير مرقّم (يرجع List مباشرة).
  Future<List<Map<String, dynamic>>> getAllPages(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final items = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      final response = await _dio.get(url, queryParameters: {
        ...?queryParameters,
        'page': page,
        'page_size': maxPageSize,
      });
      final data = response.data;
      if (data is List) {
        return items..addAll(data.cast<Map<String, dynamic>>());
      }
      items.addAll((data['results'] as List).cast<Map<String, dynamic>>());
      if (data['next'] == null) return items;
    }
  }

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
    // على الويب الـ refresh في كوكي لا نراه؛ الخادم يرد 401 إن لم يوجد
    if (refreshToken == null && !TokenStorage.usesRefreshCookie) {
      await TokenStorage.instance.clear();
      onSessionExpired();
      return null;
    }
    try {
      return await _requestRefresh(refreshToken);
    } on DioException catch (e) {
      // 401 فقط = الخادم رفض الـ refresh token (منتهٍ/غير صالح). أي شيء
      // آخر (شبكة، مهلة، 5xx) فشل مؤقت لا يُنهي الجلسة.
      if (e.response?.statusCode == 401) {
        await TokenStorage.instance.clear();
        onSessionExpired();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// طلب التجديد نفسه: [refreshToken] في الجسم للتطبيقات، و null على الويب
  /// (المتصفح يرسل الكوكي تلقائياً لنفس الأصل). يحفظ الناتج ويرجع access.
  Future<String> _requestRefresh(String? refreshToken) async {
    final response = await bareDio().post(
      ApiEndpoints.refresh,
      data: refreshToken == null ? null : {'refresh': refreshToken},
    );
    final newAccess = response.data['access'] as String;
    // ROTATE_REFRESH_TOKENS + BLACKLIST_AFTER_ROTATION: الخادم يرجع refresh
    // جديداً ويُبطل القديم، فيجب حفظه فوراً. التجديد يجري مرة واحدة فقط
    // حتى لو فشلت عدة طلبات معاً (_refreshing)، فلا يُستعمل refresh مُبطل.
    // على الويب الجديد يصل في الكوكي، لا في الجسم.
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
  }

  /// الويب فقط: بعد إعادة تحميل الصفحة لا access بالذاكرة، فنطلب واحداً
  /// بكوكي الـ refresh. true = استُعيدت الجلسة، false = لا جلسة على هذا
  /// المتصفح (401). يرمي [ApiException] عند فشل الشبكة أو الخادم.
  /// لا يستدعي [onSessionExpired]: لا جلسة هنا أصلاً لإنهائها.
  Future<bool> restoreWebSession() async {
    try {
      await _requestRefresh(null);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return false;
      throw mapError(e);
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