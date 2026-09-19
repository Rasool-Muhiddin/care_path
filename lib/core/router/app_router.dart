import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/doctor/screens/add_case_screen.dart';
import '../../features/doctor/screens/doctor_home_screen.dart';
import '../../features/engineer/screens/add_device_screen.dart';
import '../../features/engineer/screens/engineer_home_screen.dart';
import '../../features/patient/screens/patient_home_screen.dart';
import '../auth/auth_state.dart';
import '../permissions/route_guard.dart';
import 'splash_gate.dart';

/// يحوّل تغيّرات Riverpod إلى إشعارات يفهمها GoRouter (refreshListenable)
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (previous, next) => notifyListeners());
    // أعد تقييم الـ redirect فور ضغط المستخدم على "Enter" بشاشة الترحيب،
    // حتى لو كانت حالة الـ auth استقرت قبل ذلك بفترة.
    ref.listen(splashEnteredProvider, (previous, next) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/patient',
        builder: (context, state) => const PatientHomeScreen(),
        routes: [
          GoRoute(
            path: 'chat/:caseId',
            builder: (context, state) =>
                ChatScreen(caseId: int.parse(state.pathParameters['caseId']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/doctor',
        builder: (context, state) => const DoctorHomeScreen(),
        routes: [
          GoRoute(
            path: 'new-case',
            builder: (context, state) => const AddCaseScreen(),
          ),
          GoRoute(
            path: 'chat/:caseId',
            builder: (context, state) =>
                ChatScreen(caseId: int.parse(state.pathParameters['caseId']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/engineer',
        builder: (context, state) => const EngineerHomeScreen(),
        routes: [
          GoRoute(
            path: 'new-device',
            builder: (context, state) => const AddDeviceScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final hasEnteredSplash = ref.read(splashEnteredProvider);
      final location = state.matchedLocation;

      final authSettled =
          authState is AuthAuthenticated || authState is AuthUnauthenticated;

      // 1. إلى أن يضغط المستخدم "Enter" بشاشة الترحيب، أو إلى أن تستقر
      //    حالة الـ auth (أيهما أبطأ): أبقِه بشاشة الانتظار. لا يوجد حد
      //    زمني تلقائي — البقاء هنا بالكامل بيد المستخدم.
      if (!hasEnteredSplash || !authSettled) {
        return location == '/splash' ? null : '/splash';
      }

      // 2. غير مسجّل دخول: اسمح فقط بالمسارات العامة
      if (authState is AuthUnauthenticated) {
        return isPublicRoute(location) ? null : '/login';
      }

      // 3. مسجّل دخول: امنع الوصول لصفحات الدخول/الانتظار، ووجّهه لفرعه
      if (authState is AuthAuthenticated) {
        final role = authState.user.role;

        if (location == '/login' || location == '/splash') {
          return role.homeRoute;
        }

        // امنع الوصول لفرع دور آخر (مثلاً مريض يحاول فتح /doctor)
        if (!isRouteAllowedForRole(location, role)) {
          return role.homeRoute;
        }
      }

      return null; // لا حاجة لإعادة توجيه
    },
  );
});