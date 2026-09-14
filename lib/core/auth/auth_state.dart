import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
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
    final hasTokens = await TokenStorage.instance.hasTokens;
    if (!hasTokens) {
      state = const AuthUnauthenticated();
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).fetchCurrentUser();
      state = AuthAuthenticated(user);
    } catch (_) {
      await TokenStorage.instance.clear();
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login({required String username, required String password}) async {
    state = const AuthLoading();
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

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthUnauthenticated();
  }
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);
