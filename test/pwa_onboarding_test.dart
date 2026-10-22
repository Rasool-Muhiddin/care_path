import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/user_model.dart';
import 'package:axon/core/notifications/web_push.dart';
import 'package:axon/core/pwa/pwa_onboarding.dart';
import 'package:axon/core/pwa/pwa_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
  final AuthStatus _initial;
  @override
  AuthStatus build() => _initial;
}

class _FakePwa extends PwaStatusNotifier {
  _FakePwa(this._initial);
  final PwaStatus _initial;
  int enableCalls = 0;
  @override
  PwaStatus build() => _initial;
  @override
  Future<WebPushPermission> enableNotifications() async {
    enableCalls++;
    state = state.copyWith(permission: WebPushPermission.granted);
    return WebPushPermission.granted;
  }
}

PwaStatus _web({bool installed = true, bool configured = true, WebPushPermission permission = WebPushPermission.notAsked}) =>
    PwaStatus(isWeb: true, isIPhone: true, installed: installed, pushConfigured: configured, permission: permission);

AuthStatus _user(String role) => AuthAuthenticated(UserModel.fromJson(
      {'id': 1, 'username': 'u', 'first_name': 'A', 'last_name': 'B', 'role': role},
    ));

const _appKey = Key('app');

Future<_FakePwa> _pump(WidgetTester tester, PwaStatus status, AuthStatus auth) async {
  final pwa = _FakePwa(status);
  // iPhone 14/15 بالنقاط المنطقية
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pwaStatusProvider.overrideWith(() => pwa),
      authStateProvider.overrideWith(() => _FakeAuth(auth)),
    ],
    child: MaterialApp(
      builder: (context, child) => PwaOnboardingGate(child: child!),
      home: const Scaffold(key: _appKey, body: Text('APP')),
    ),
  ));
  await tester.pump();
  return pwa;
}

Future<void> _continueInBrowser(WidgetTester tester) async {
  final button = find.text('المتابعة في المتصفح بدون إشعارات');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  // لمسة خارج الشاشة = خطأ في الاختبار، لا تحذير صامت
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  testWidgets('native app: nothing is added', (tester) async {
    await _pump(tester, PwaStatus.native, _user('patient'));
    expect(find.text('APP'), findsOneWidget);
    expect(find.byType(InstallGuideScreen), findsNothing);
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
  });

  testWidgets('iPhone Safari (not installed): Arabic install guide, can continue in browser', (tester) async {
    await _pump(tester, _web(installed: false, permission: WebPushPermission.unsupported), const AuthUnauthenticated());
    expect(find.byType(InstallGuideScreen), findsOneWidget);
    expect(find.textContaining('إضافة إلى الشاشة الرئيسية'), findsWidgets);
    expect(find.textContaining('الإشعارات لا تعمل إلا بعد التثبيت'), findsOneWidget);

    await _continueInBrowser(tester);
    expect(find.byType(InstallGuideScreen), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('continued in Safari and logged in: banner offers the install guide again', (tester) async {
    await _pump(tester, _web(installed: false, permission: WebPushPermission.unsupported), _user('patient'));
    await _continueInBrowser(tester);
    expect(find.text('ثبّت التطبيق على الشاشة الرئيسية لتصلك الإشعارات.'), findsOneWidget);
    await tester.tap(find.text('كيف؟'));
    await tester.pump();
    expect(find.byType(InstallGuideScreen), findsOneWidget);
  });

  testWidgets('installed, patient logged in: Arabic prompt; Enable asks once and clears the warning', (tester) async {
    final pwa = await _pump(tester, _web(), _user('patient'));
    expect(find.text('فعّل الإشعارات'), findsOneWidget);
    expect(find.text('الإشعارات غير مفعّلة — لن تصلك تنبيهات الرسائل الجديدة.'), findsOneWidget);

    await tester.tap(find.text('تفعيل الإشعارات'));
    await tester.pump();
    await tester.pump();
    expect(pwa.enableCalls, 1);
    expect(find.text('فعّل الإشعارات'), findsNothing);
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('"Not now" keeps a visible warning (English for staff)', (tester) async {
    final pwa = await _pump(tester, _web(), _user('doctor'));
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('Turn on notifications'), findsNothing);
    expect(find.text("Notifications are off — you won't be alerted to new messages."), findsOneWidget);

    await tester.tap(find.text('Enable'));
    await tester.pump();
    expect(pwa.enableCalls, 1);
  });

  testWidgets('blocked notifications: warning explains iPhone Settings, no prompt', (tester) async {
    await _pump(tester, _web(permission: WebPushPermission.denied), _user('patient'));
    expect(find.text('فعّل الإشعارات'), findsNothing);
    expect(find.textContaining('إعدادات iPhone'), findsOneWidget);
  });

  testWidgets('no warning before login, when enabled, or when push is not configured', (tester) async {
    await _pump(tester, _web(), const AuthUnauthenticated());
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);

    await _pump(tester, _web(permission: WebPushPermission.granted), _user('patient'));
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);

    await _pump(tester, _web(configured: false), _user('patient'));
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
    expect(find.text('فعّل الإشعارات'), findsNothing);
  });

  testWidgets('showing and clearing the banner keeps the app screen (no remount)', (tester) async {
    final pwa = await _pump(tester, _web(), _user('patient'));
    final before = tester.state(find.byType(Navigator));
    await tester.tap(find.text('تفعيل الإشعارات'));
    await tester.pump();
    await tester.pump();
    expect(pwa.enableCalls, 1);
    expect(identical(tester.state(find.byType(Navigator)), before), isTrue);
  });
}
