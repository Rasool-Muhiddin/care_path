import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/fcm_service.dart';
import '../notifications/web_push.dart';

/// حالة نسخة الويب (PWA) كما تحتاجها شاشات التثبيت والإشعارات. على
/// أندرويد/iOS الأصليين: [isWeb] = false فلا تظهر أي منها.
@immutable
class PwaStatus {
  const PwaStatus({
    required this.isWeb,
    required this.isIPhone,
    required this.installed,
    required this.pushConfigured,
    required this.permission,
  });

  static const native = PwaStatus(
    isWeb: false,
    isIPhone: false,
    installed: false,
    pushConfigured: false,
    permission: WebPushPermission.unsupported,
  );

  final bool isWeb;

  /// iPhone/iPod (متصفح على iOS). iPad بوضع سطح المكتب يعرّف نفسه كـ Mac.
  final bool isIPhone;

  /// مفتوح من أيقونة الشاشة الرئيسية (وليس تبويب Safari)
  final bool installed;

  /// النسخة مبنية بإعداد Firebase للويب (web_firebase.json)
  final bool pushConfigured;
  final WebPushPermission permission;

  /// iPhone في Safari ولم يُثبَّت: نعرض شرح "إضافة إلى الشاشة الرئيسية"
  bool get needsInstall => isWeb && isIPhone && !installed;

  /// الإشعارات ممكنة لكنها غير مفعّلة: نعرض التنبيه
  bool get notificationsOff => isWeb && pushConfigured && permission != WebPushPermission.granted;

  PwaStatus copyWith({WebPushPermission? permission}) => PwaStatus(
        isWeb: isWeb,
        isIPhone: isIPhone,
        installed: installed,
        pushConfigured: pushConfigured,
        permission: permission ?? this.permission,
      );
}

class PwaStatusNotifier extends Notifier<PwaStatus> {
  AppLifecycleListener? _lifecycle;

  @override
  PwaStatus build() {
    if (!kIsWeb) return PwaStatus.native;
    // قد يفعّل المستخدم الإشعارات من إعدادات iPhone ثم يرجع للتطبيق
    _lifecycle ??= AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _lifecycle?.dispose();
      _lifecycle = null;
    });
    return PwaStatus(
      isWeb: true,
      isIPhone: defaultTargetPlatform == TargetPlatform.iOS,
      installed: isInstalledWebApp(),
      pushConfigured: FcmService.instance.webPushConfigured,
      permission: webPushPermission(),
    );
  }

  void refresh() {
    if (state.isWeb) state = state.copyWith(permission: webPushPermission());
  }

  /// من لمسة زر "تفعيل الإشعارات" مباشرة: الطلب يحدث داخل اللمسة (iOS).
  Future<WebPushPermission> enableNotifications() async {
    final permission = await FcmService.instance.enableWebPush();
    state = state.copyWith(permission: permission);
    return permission;
  }
}

final pwaStatusProvider = NotifierProvider<PwaStatusNotifier, PwaStatus>(PwaStatusNotifier.new);
