import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../auth/token_storage.dart';
import '../permissions/user_role.dart';
import '../router/app_router.dart';
import 'fcm_repository.dart';
import 'global_keys.dart';

/// يُستدعى عندما تصل رسالة FCM ونظام التشغيل يشغّل التطبيق بالخلفية/من
/// جديد لمعالجتها. يجب أن تبقى top-level (وليست method داخل class)
/// ومعلَّمة بـ @pragma('vm:entry-point') حتى لا يحذفها tree-shaking عند
/// بناء نسخة release. مسجَّلة من main.dart عبر
/// FirebaseMessaging.onBackgroundMessage.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // لا حاجة لأي منطق هنا حالياً: نظام التشغيل هو من يعرض الإشعار تلقائياً
  // من حقل "notification" بالرسالة عندما يكون التطبيق بالخلفية أو مغلقاً.
  // هذه الدالة موجودة فقط لأن الحزمة تتطلب تسجيل معالج خلفية صراحةً.
}

/// طبقة واحدة تُدير كل ما يخص FCM: تسجيل/حذف توكن الجهاز، عرض رسائل
/// المقدمة، والتنقّل عند الضغط على إشعار. تُهيَّأ مرة واحدة عند تسجيل
/// الدخول (من main.dart عبر الاستماع لـ authStateProvider) وتُفكَّك عند
/// تسجيل الخروج.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  WidgetRef? _ref;
  String? _currentToken;
  bool _initialized = false;
  // اشتراكات FCM الحالية — تُلغى عند الخروج حتى لا تتكرر بعد كل دخول جديد
  // (SnackBar مزدوج، أو فتح شاشة المحادثة مرتين عند الضغط على إشعار).
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  // getInitialMessage يخص فتح التطبيق نفسه: يُعالج مرة واحدة فقط لكل تشغيل
  bool _initialMessageHandled = false;

  final _chatMessages = StreamController<int>.broadcast();

  /// رقم الحالة (case_id) لكل رسالة محادثة تصل والتطبيق مفتوح — تستمع لها
  /// شاشة المحادثة وعدّاد غير المقروء ليتحدّثا فوراً بدل انتظار الـ polling.
  Stream<int> get chatMessages => _chatMessages.stream;

  FcmRepository get _repository => FcmRepository(_ref!.read(apiClientProvider));

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<void> init(WidgetRef ref) async {
    if (_initialized) return;
    _initialized = true;
    _ref = ref;

    try {
      // الاشتراك أولاً وبشكل متزامن: لو سجّل المستخدم خروجه أثناء الانتظار
      // بالأسفل، تلغيها teardown كلها ولا يبقى اشتراك يتيم.
      _subscriptions.addAll([
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          _currentToken = newToken;
          _repository.registerToken(token: newToken, platform: _platform);
        }),
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage),
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap),
      ]);

      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      // خرج المستخدم أثناء الانتظار: لا نسجّل توكناً لحساب لم يعد موجوداً
      if (!_initialized) return;
      if (token != null) {
        _currentToken = token;
        await _repository.registerToken(token: token, platform: _platform);
      }

      // إن فُتح التطبيق من صفر بالضغط على إشعار (وليس فقط من الخلفية)
      if (!_initialMessageHandled) {
        _initialMessageHandled = true;
        final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null && _initialized) {
          _handleNotificationTap(initialMessage);
        }
      }
    } catch (_) {
      // غياب google-services.json أو فشل الشبكة لا يجب أن يعطّل تسجيل الدخول
    }
  }

  /// يُستدعى عند تسجيل الخروج — يحذف توكن هذا الجهاز من الخادم حتى لا
  /// يستمر بتلقي إشعارات تخص حساباً لم يعد مسجَّلاً دخوله عليه.
  ///
  /// يجب استدعاؤها قبل مسح JWT (AuthNotifier.logout يفعل ذلك) حتى يكون
  /// طلب الحذف مصادَقاً. الحقول تُصفَّر قبل أي انتظار حتى لا يتكرر الحذف
  /// لو استُدعيت مرة ثانية أثناء الطلب (مسار انتهاء الجلسة).
  Future<void> teardown() async {
    final token = _currentToken;
    final repository = _ref != null ? _repository : null;
    _currentToken = null;
    _initialized = false;
    _ref = null;
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }

    // بلا JWT صالح سيُرفض الحذف أصلاً (الجلسة انتهت) — لا داعي للطلب
    if (token == null || repository == null || !await TokenStorage.instance.hasTokens) {
      return;
    }
    // لا نؤخّر تسجيل الخروج طويلاً إن كانت الشبكة بطيئة
    await repository
        .unregisterToken(token)
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// عرض بسيط داخل التطبيق عند وصول رسالة والتطبيق مفتوح بالمقدمة —
  /// أندرويد لا يعرض إشعار النظام تلقائياً في هذه الحالة.
  void _handleForegroundMessage(RemoteMessage message) {
    if (message.data['type'] == 'chat_message') {
      final caseId = int.tryParse('${message.data['case_id']}');
      if (caseId != null) _chatMessages.add(caseId);
    }
    final notification = message.notification;
    if (notification == null) return;
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          [
            notification.title,
            notification.body,
          ].where((s) => s != null && s.isNotEmpty).join(': '),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// عند الضغط على الإشعار (سواء التطبيق بالخلفية أو كان مغلقاً تماماً):
  /// ننتقل مباشرة لشاشة محادثة الحالة المعنية إن كان دور المستخدم يدعمها.
  void _handleNotificationTap(RemoteMessage message) {
    final ref = _ref;
    if (ref == null) return;
    if (message.data['type'] != 'chat_message') return;

    final caseId = message.data['case_id'];
    if (caseId == null) return;

    final authState = ref.read(authStateProvider);
    if (authState is! AuthAuthenticated) return;

    // شاشة المحادثة مُعرَّفة فقط ضمن فرعي المريض والطبيب بالراوتر الحالي.
    final role = authState.user.role;
    if (role != UserRole.patient && role != UserRole.doctor) return;

    ref.read(appRouterProvider).push('/${role.name}/chat/$caseId');
  }
}