import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/user_model.dart';
import 'package:axon/core/notifications/web_push.dart';
import 'package:axon/core/pwa/pwa_onboarding.dart';
import 'package:axon/core/pwa/pwa_status.dart';
import 'package:axon/core/update/web_update_provider.dart';
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
  @override
  PwaStatus build() => _initial;
}

class _UpdateReady extends WebUpdateNotifier {
  @override
  bool build() => true;
}

AuthStatus _user(String role) => AuthAuthenticated(UserModel.fromJson(
      {'id': 1, 'username': 'u', 'first_name': 'A', 'last_name': 'B', 'role': role},
    ));

const _installedWeb = PwaStatus(
  isWeb: true,
  isIPhone: true,
  installed: true,
  pushConfigured: true,
  permission: WebPushPermission.granted,
);

Future<void> _pump(WidgetTester tester, PwaStatus pwa, AuthStatus auth) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      pwaStatusProvider.overrideWith(() => _FakePwa(pwa)),
      authStateProvider.overrideWith(() => _FakeAuth(auth)),
      webUpdateProvider.overrideWith(_UpdateReady.new),
    ],
    child: MaterialApp(
      builder: (context, child) => PwaOnboardingGate(child: child!),
      home: const Scaffold(body: Text('APP')),
    ),
  ));
  await tester.pump();
}

void main() {
  tearDown(() {
    WebUpdateNotifier.debugIsWeb = null;
    WebUpdateNotifier.debugRunningBuild = null;
  });

  test('version.json build number is read from "axon_build"', () {
    expect(parseWebBuild({'version': '0.1.7', 'axon_build': '1761300000'}), 1761300000);
    expect(parseWebBuild({'version': '0.1.7'}), isNull);
    expect(parseWebBuild('not json'), isNull);
  });

  Future<ProviderContainer> container(int? serverBuild, {void Function()? onFetch}) async {
    final c = ProviderContainer(overrides: [
      latestWebBuildProvider.overrideWithValue(() async {
        onFetch?.call();
        return serverBuild;
      }),
    ]);
    addTearDown(c.dispose);
    c.read(webUpdateProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  testWidgets('a newer build on the server turns the banner on; same or older does not', (tester) async {
    WebUpdateNotifier.debugIsWeb = true;
    WebUpdateNotifier.debugRunningBuild = 100;
    await tester.runAsync(() async {
      expect((await container(101)).read(webUpdateProvider), isTrue);
      expect((await container(100)).read(webUpdateProvider), isFalse);
      expect((await container(99)).read(webUpdateProvider), isFalse);
      expect((await container(null)).read(webUpdateProvider), isFalse);
    });
  });

  testWidgets('native app or a build without a build number never checks', (tester) async {
    var fetches = 0;
    await tester.runAsync(() async {
      WebUpdateNotifier.debugIsWeb = false;
      WebUpdateNotifier.debugRunningBuild = 100;
      expect((await container(200, onFetch: () => fetches++)).read(webUpdateProvider), isFalse);
      WebUpdateNotifier.debugIsWeb = true;
      WebUpdateNotifier.debugRunningBuild = 0;
      expect((await container(200, onFetch: () => fetches++)).read(webUpdateProvider), isFalse);
    });
    expect(fetches, 0);
  });

  testWidgets('update banner is Arabic for the patient and does not block the app', (tester) async {
    await _pump(tester, _installedWeb, _user('patient'));
    expect(find.text('يتوفر إصدار جديد من التطبيق.'), findsOneWidget);
    expect(find.text('تحديث'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('update banner is English for staff', (tester) async {
    await _pump(tester, _installedWeb, _user('doctor'));
    expect(find.text('A new version is available.'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('update banner also shows on the (English) login screen', (tester) async {
    await _pump(tester, _installedWeb, const AuthUnauthenticated());
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('update and notifications banners stack without overflow', (tester) async {
    await _pump(tester, _installedWeb.copyWith(permission: WebPushPermission.notAsked), _user('doctor'));
    expect(find.text('Update'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native app: no update banner', (tester) async {
    await _pump(tester, PwaStatus.native, _user('doctor'));
    expect(find.text('Update'), findsNothing);
  });
}
