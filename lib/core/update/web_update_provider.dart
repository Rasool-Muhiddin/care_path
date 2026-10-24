import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// رقم بناء نسخة الويب التي تعمل الآن. tool/build_web.sh يمرّره
/// (--dart-define=AXON_WEB_BUILD=<unix time>) ويكتب الرقم نفسه في
/// build/web/version.json كـ "axon_build". 0 = بناء بدون السكربت (flutter
/// run مثلاً): لا فحص.
const runningWebBuild = int.fromEnvironment('AXON_WEB_BUILD');

/// "axon_build" من version.json، أو null إن لم يوجد.
@visibleForTesting
int? parseWebBuild(Object? json) {
  if (json is! Map) return null;
  return int.tryParse('${json['axon_build'] ?? ''}');
}

/// يجلب رقم البناء المنشور على الخادم. رابط فريد في كل مرة (?t=) حتى لا
/// يرجع المتصفح أو Cloudflare نسخة مخزَّنة من version.json.
final latestWebBuildProvider = Provider<Future<int?> Function()>((ref) {
  return () async {
    final url = Uri.base.resolve('version.json').replace(
      queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
    ));
    final response = await dio.getUri<Object?>(url);
    return parseWebBuild(response.data);
  };
});

/// true = يوجد على الخادم بناء ويب أحدث من الذي يعمل الآن (يظهر تنبيه
/// "يتوفر إصدار جديد" في PwaOnboardingGate). يُفحص عند التشغيل، وعند
/// الرجوع للتطبيق (iPhone يُبقي الصفحة القديمة حيّة في الخلفية بلا إعادة
/// تحميل)، وكل 30 دقيقة لتبويب يبقى مفتوحاً. أندرويد/iOS الأصليان: false دائماً.
class WebUpdateNotifier extends Notifier<bool> {
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  DateTime? _lastCheck;

  /// للاختبارات: kIsWeb ثابت على الـ VM
  @visibleForTesting
  static bool? debugIsWeb;
  @visibleForTesting
  static int? debugRunningBuild;

  int get _running => debugRunningBuild ?? runningWebBuild;

  @override
  bool build() {
    if (!(debugIsWeb ?? kIsWeb) || _running == 0) return false;
    _lifecycle ??= AppLifecycleListener(onResume: check);
    _timer ??= Timer.periodic(const Duration(minutes: 30), (_) => check());
    ref.onDispose(() {
      _lifecycle?.dispose();
      _lifecycle = null;
      _timer?.cancel();
      _timer = null;
    });
    Future.microtask(check);
    return false;
  }

  Future<void> check() async {
    if (state) return; // التنبيه ظاهر أصلاً
    final now = DateTime.now();
    // الرجوع للتطبيق يتكرر كثيراً (فتح الكاميرا، التبديل بين التطبيقات)
    if (_lastCheck != null && now.difference(_lastCheck!) < const Duration(seconds: 30)) return;
    _lastCheck = now;
    try {
      final latest = await ref.read(latestWebBuildProvider)();
      if (latest != null && latest > _running) state = true;
    } catch (_) {
      // بلا شبكة: نعيد المحاولة عند الرجوع التالي للتطبيق
    }
  }
}

final webUpdateProvider = NotifierProvider<WebUpdateNotifier, bool>(WebUpdateNotifier.new);
