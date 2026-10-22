import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../auth/token_storage.dart';
import '../router/app_router.dart';
import 'fcm_repository.dart';
import 'firebase_web_options.dart';
import 'global_keys.dart';
import 'web_push.dart';

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

  /// نسخ iOS الحالية موقّعة بحساب Apple مجاني (Sideloadly) بلا صلاحية
  /// APNs، فالإشعارات معطّلة عليها كلياً ولا يُطلب إذنها. بعد الاشتراك
  /// بالعضوية المدفوعة وإعداد APNs: --dart-define=IOS_PUSH_ENABLED=true
  static const _iosPushEnabled = bool.fromEnvironment('IOS_PUSH_ENABLED');

  /// تطبيق iOS الأصلي فقط. على الويب defaultTargetPlatform يتبع نظام
  /// المتصفح (iPhone = iOS)، لكن نسخة الويب تستعمل Web Push وليس APNs.
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  String get _platform => kIsWeb ? 'web' : (_isIOS ? 'ios' : 'android');

  /// نسخة الويب مبنية بإعداد Firebase للويب وتم تهيئته
  bool get webPushConfigured => kIsWeb && FirebaseWebConfig.isConfigured && Firebase.apps.isNotEmpty;

  /// إذن إشعارات المتصفح الآن (للتنبيه والزر في الواجهة)
  WebPushPermission get webPermission => webPushPermission();

  Future<void> init(WidgetRef ref) async {
    if (_initialized) return;
    if (_isIOS && !_iosPushEnabled) return;
    if (kIsWeb) return _initWeb(ref);
    _initialized = true;
    _ref = ref;

    try {
      // الاشتراك أولاً وبشكل متزامن: لو سجّل المستخدم خروجه أثناء الانتظار
      // بالأسفل، تلغيها teardown كلها ولا يبقى اشتراك يتيم.
      _subscriptions.addAll([
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          if (newToken.isEmpty) return;
          _currentToken = newToken;
          _repository.registerToken(token: newToken, platform: _platform);
        }),
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage),
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap),
      ]);

      await FirebaseMessaging.instance.requestPermission();
      // على iOS يرمي getToken استثناءً ما لم يصل توكن APNs أولاً (إذن
      // مرفوض أو توقيع بلا صلاحية push) — نتخطّى التسجيل حينها فقط.
      final hasApns = !_isIOS || await _waitForApnsToken();
      final token = hasApns ? await FirebaseMessaging.instance.getToken() : null;
      // خرج المستخدم أثناء الانتظار: لا نسجّل توكناً لحساب لم يعد موجوداً
      if (!_initialized) return;
      if (token != null && token.isNotEmpty) {
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
    } catch (e) {
      // غياب google-services.json / GoogleService-Info.plist أو فشل الشبكة
      // لا يجب أن يعطّل تسجيل الدخول
      if (kDebugMode) debugPrint('FCM init skipped: $e');
    }
  }

  /// الويب: لا يُطلب الإذن هنا أبداً (Safari يرفضه خارج لمسة المستخدم) —
  /// يُطلب من زر "تفعيل الإشعارات" عبر [enableWebPush]. إن كان ممنوحاً من
  /// قبل يُسجَّل التوكن مباشرة. الإشعارات تصل للـ service worker، وهو يرسل
  /// للصفحة المفتوحة (webPushEvents) بدل onMessage/onMessageOpenedApp.
  Future<void> _initWeb(WidgetRef ref) async {
    if (!webPushConfigured) return;
    _initialized = true;
    _ref = ref;
    _subscriptions.add(webPushEvents().listen((event) {
      if (event.clicked) {
        _openChat(event.type, event.caseId);
      } else if (event.type == 'chat_message' && event.caseId != null) {
        _chatMessages.add(event.caseId!);
      }
    }));
    if (!_initialMessageHandled) {
      _initialMessageHandled = true;
      final initial = initialWebPushEvent();
      if (initial != null) _openChat(initial.type, initial.caseId);
    }
    if (webPermission == WebPushPermission.granted) await _registerWebToken();
  }

  /// من زر "تفعيل الإشعارات" فقط. طلب الإذن هو أول ما يحدث (متزامناً داخل
  /// اللمسة، كما يشترط iOS)، ثم تسجيل توكن الويب في الخادم.
  Future<WebPushPermission> enableWebPush() async {
    final permission = await requestWebPushPermission();
    if (permission == WebPushPermission.granted && _initialized) await _registerWebToken();
    return permission;
  }

  Future<void> _registerWebToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken(vapidKey: FirebaseWebConfig.vapidKey);
      if (!_initialized || token == null || token.isEmpty) return;
      _currentToken = token;
      await _repository.registerToken(token: token, platform: _platform);
    } catch (e) {
      // service worker غير متاح (مثلاً /firebase-messaging-sw.js لا يُقدَّم) —
      // التطبيق يعمل بلا إشعارات
      if (kDebugMode) debugPrint('Web push registration failed: $e');
    }
  }

  /// توكن APNs قد يتأخر قليلاً بعد منح الإذن — ننتظره بضع ثوانٍ فقط.
  Future<bool> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (await FirebaseMessaging.instance.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  /// يُستدعى عند تسجيل الخروج — يحذف توكن هذا الجهاز من الخادم حتى لا
  /// يستمر بتلقي إشعارات تخص حساباً لم يعد مسجَّلاً دخوله عليه.
  ///
  /// يجب استدعاؤها قبل مسح JWT (AuthNotifier.logout يفعل ذلك) حتى يكون
  /// طلب الحذف مصادَقاً. الحقول تُصفَّر قبل أي انتظار حتى لا يتكرر الحذف
  /// لو استُدعيت مرة ثانية أثناء الطلب (مسار انتهاء الجلسة).
  ///
  /// [serverAlreadyCleared]: بعد حذف الحساب — الخادم حذف رموز الإشعارات
  /// بنفسه والـ JWT لم يعد صالحاً، فلا طلب للخادم؛ يُحذف توكن FCM من
  /// الجهاز نفسه حتى يحصل أي حساب لاحق على توكن جديد.
  Future<void> teardown({bool serverAlreadyCleared = false}) async {
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

    if (serverAlreadyCleared) {
      try {
        await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 5));
      } catch (_) {
        // بلا Firebase (أو بلا شبكة) لا يوجد ما يُحذف محلياً
      }
      return;
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
    _openChat('${message.data['type']}', int.tryParse('${message.data['case_id']}'));
  }

  void _openChat(String type, int? caseId) {
    final ref = _ref;
    if (ref == null) return;
    if (type != 'chat_message' || caseId == null) return;

    final authState = ref.read(authStateProvider);
    if (authState is! AuthAuthenticated) return;

    // بعض الأدوار ليس لها مسار محادثة في الراوتر (UserRole.chatRoute)
    final route = authState.user.role.chatRoute(caseId);
    if (route == null) return;

    ref.read(appRouterProvider).push(route);
  }
}