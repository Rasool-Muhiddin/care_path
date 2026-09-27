import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_state.dart';
import 'core/notifications/fcm_service.dart';
import 'core/notifications/global_keys.dart';
import 'core/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // يقرأ android/app/google-services.json تلقائياً — بدونه هذا الاستدعاء
  // يفشل، لذا نلفّه بمحاولة حتى يبقى التطبيق يعمل قبل إعداد Firebase.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {
    // Firebase غير مُعدّ بعد (google-services.json غير موجود) — الإشعارات
    // فقط ستكون معطّلة، وبقية التطبيق يعمل بشكل طبيعي.
  }
  runApp(const ProviderScope(child: AxonApp()));
}

class AxonApp extends ConsumerWidget {
  const AxonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // تهيئة/تفكيك FCM يتبع حالة تسجيل الدخول تلقائياً: تسجيل توكن الجهاز
    // فور نجاح الدخول (أو استعادة الجلسة)، وحذفه فور الخروج.
    ref.listen<AuthStatus>(authStateProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        FcmService.instance.init(ref);
      } else if (next is AuthUnauthenticated) {
        FcmService.instance.teardown();
      }
    });

    return MaterialApp.router(
      title: 'axon',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      // TODO: عدّل الثيم لاحقاً حسب هوية العلامة التجارية
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      routerConfig: router,
      // دعم اللغة العربية والاتجاه من اليمين لليسار
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
