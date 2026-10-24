import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/data/voice_cache.dart';
import '../network/api_client.dart';
import '../notifications/fcm_service.dart';
import '../permissions/user_role.dart';
import 'auth_repository.dart';
import 'token_storage.dart';
import 'user_model.dart';

/// الحالات الممكنة للمصادقة
sealed class AuthStatus {
  const AuthStatus();
}

class AuthInitial extends AuthStatus {
  const AuthInitial();
}

class AuthLoading extends AuthStatus {
  const AuthLoading();
}

class AuthAuthenticated extends AuthStatus {
  final UserModel user;
  const AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthStatus {
  final String? errorMessage;
  const AuthUnauthenticated({this.errorMessage});
}

/// توكنات محفوظة لكن تعذّر التحقق منها الآن (لا إنترنت، مهلة، خطأ خادم).
/// المستخدم يبقى مسجّل دخوله؛ شاشة البداية تعرض [message] وزر إعادة
/// المحاولة (AuthNotifier.retry).
class AuthOffline extends AuthStatus {
  final String message;
  const AuthOffline(this.message);
}

/// provider لـ ApiClient — onSessionExpired يُربط بـ AuthNotifier لاحقاً
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    onSessionExpired: () {
      ref.read(authStateProvider.notifier).logout();
    },
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider));
});

/// النقطة المركزية لحالة تسجيل الدخول — يستمع لها app_router.dart
/// لإعادة التوجيه تلقائياً، وتستخدمها كل الشاشات لمعرفة المستخدم الحالي
class AuthNotifier extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    // عند إنشاء الـ provider لأول مرة: نحاول استعادة الجلسة من التخزين
    _tryRestoreSession();
    return const AuthInitial();
  }

  Future<void> _tryRestoreSession() async {
    state = const AuthLoading();
    // الويب: بعد إعادة تحميل الصفحة يضيع access (بالذاكرة فقط) — نستعيده
    // بصمت من كوكي الـ refresh قبل أي شيء.
    if (TokenStorage.usesRefreshCookie && !await TokenStorage.instance.hasTokens) {
      try {
        if (!await ref.read(apiClientProvider).restoreWebSession()) {
          state = const AuthUnauthenticated();
          return;
        }
      } on ApiException catch (e) {
        // لا نعرف إن كانت هناك جلسة (الكوكي لا يُقرأ من Dart)؛ نعرض إعادة المحاولة
        state = AuthOffline(e.message);
        return;
      }
    }
    final hasTokens = await TokenStorage.instance.hasTokens;
    if (!hasTokens) {
      state = const AuthUnauthenticated();
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).fetchCurrentUser();
      state = AuthAuthenticated(user);
    } on ApiException catch (e) {
      // ApiClient يمسح التوكنات فقط عندما يرفض الخادم الـ refresh token
      // نفسه (401). إن بقيت التوكنات فالفشل مؤقت (شبكة/مهلة/خادم) —
      // لا نسجّل خروج المستخدم، بل نعرض حالة عدم الاتصال مع إعادة المحاولة.
      if (await TokenStorage.instance.hasTokens) {
        state = AuthOffline(e.message);
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      // استجابة غير مفهومة (مثلاً دور غير معروف) — الجلسة غير صالحة للاستخدام
      await TokenStorage.instance.clear();
      state = const AuthUnauthenticated();
    }
  }

  /// يُستدعى من زر "إعادة المحاولة" عند [AuthOffline]
  Future<void> retry() => _tryRestoreSession();

  Future<void> login({required String username, required String password}) async {
    state = const AuthLoading();
    // خروج سابق ما زال ينظّف بالخلفية: ننتظره حتى لا يمسح التوكنات الجديدة
    // (مقيَّد بمهلتي الطلبين، 5 ثوانٍ لكل منهما)
    await _pendingLogout;
    try {
      final user = await ref.read(authRepositoryProvider).login(
            username: username,
            password: password,
          );
      state = AuthAuthenticated(user);
    } catch (e) {
      state = AuthUnauthenticated(errorMessage: e.toString());
    }
  }

  /// تنظيف الخادم لخروج جارٍ (null إن لم يوجد)
  Future<void>? _pendingLogout;

  /// الواجهة تنتقل لشاشة الدخول فوراً (الـ router يستبدل كل المكدّس، فلا
  /// رجوع لشاشات الحساب)، وطلبات الخادم تكمل بالخلفية. الـ Future يكتمل
  /// بعد انتهائها — لا داعي لانتظاره من الواجهة.
  Future<void> logout() {
    final pending = _pendingLogout;
    // مسار انتهاء الجلسة قد يستدعيها مجدداً أثناء التنظيف
    if (pending != null) return pending;

    // teardown تُصفّر حالة FCM متزامناً ثم ترسل حذف التوكن بالخلفية؛ يجب أن
    // تبدأ قبل مسح JWT وإلا يُرسل الطلب بلا مصادقة فيُرفض، ويستمر الجهاز
    // باستقبال إشعارات الحساب بعد الخروج. ولأنها تُستدعى قبل تغيير الحالة،
    // يصبح استدعاء main.dart لها عند AuthUnauthenticated بلا أثر.
    final fcm = FcmService.instance.teardown();
    state = const AuthUnauthenticated();
    // الرسائل الصوتية المحمّلة مراسلات طبية: لا تبقى على الجهاز بعد الخروج.
    unawaited(VoiceCache.clear());

    return _pendingLogout = () async {
      try {
        await fcm;
      } catch (_) {}
      // يُبطل الـ refresh في الخادم ثم يمسح التوكنات محلياً (مهلة 5 ثوانٍ)
      await ref.read(authRepositoryProvider).logout();
    }()
        .whenComplete(() => _pendingLogout = null);
  }

  /// الخروج بعد نجاح حذف الحساب (AuthRepository.deleteAccount). الخادم حذف
  /// الحساب وأبطل توكناته ورموز إشعاراته، فالتنظيف هنا محلي فقط (أي طلب
  /// مصادَق الآن يُرفض بـ 401).
  Future<void> signOutAfterAccountDeletion() async {
    await FcmService.instance.teardown(serverAlreadyCleared: true);
    await TokenStorage.instance.clear();
    state = const AuthUnauthenticated();
    unawaited(VoiceCache.clear());
  }
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);

/// هل المستخدم الحالي مدير المهندسين؟ — لإخفاء الأزرار التي لا يملكها
/// المهندس العادي (إضافة/تعديل العيادات وأنواع الأجهزة، القناة الطبية...).
final isManagerProvider = Provider<bool>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth is AuthAuthenticated && auth.user.role == UserRole.engineer && auth.user.isManager;
});
