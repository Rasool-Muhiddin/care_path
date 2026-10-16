import 'package:axon/core/auth/auth_repository.dart';
import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/token_storage.dart';
import 'package:axon/core/auth/user_model.dart';
import 'package:axon/core/network/api_client.dart';
import 'package:axon/core/permissions/user_role.dart';
import 'package:axon/core/widgets/account_menu.dart';
import 'package:axon/features/chat/data/chat_message_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._status);
  final AuthStatus _status;
  @override
  AuthStatus build() => _status;
}

class _FakeRepo extends AuthRepository {
  _FakeRepo({this.blocked, this.wrongPassword = false}) : super(ApiClient(onSessionExpired: () {}));
  final AccountDeletionBlocked? blocked;
  final bool wrongPassword;
  String? deletedWith;

  @override
  Future<void> checkAccountDeletion() async {
    if (blocked != null) throw blocked!;
  }

  @override
  Future<void> deleteAccount(String password) async {
    if (wrongPassword) throw ApiException('كلمة المرور غير صحيحة.', statusCode: 400);
    deletedWith = password;
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, UserRole role, _FakeRepo repo) async {
  final strings = role == UserRole.patient ? AccountMenuStrings.ar : AccountMenuStrings.en;
  final container = ProviderContainer(overrides: [
    authStateProvider.overrideWith(
      () => _FakeAuth(AuthAuthenticated(UserModel(id: 1, username: 'u', email: '', role: role))),
    ),
    authRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [AccountMenuButton(strings: strings)])),
    ),
  ));
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({
        'axon_access_token': 'a',
        'axon_refresh_token': 'r',
      }));

  testWidgets('patient: explain -> password -> confirm -> deleted and signed out', (tester) async {
    final repo = _FakeRepo();
    final container = await _pump(tester, UserRole.patient, repo);

    await tester.tap(find.text('حذف الحساب'));
    await tester.pumpAndSettle();
    expect(find.textContaining('النوبات المسجّلة'), findsOneWidget); // what will be deleted
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'my-password');
    await tester.pump();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    expect(find.text('حذف حسابك؟'), findsOneWidget); // final confirmation
    await tester.tap(find.widgetWithText(FilledButton, 'حذف الحساب'));
    await tester.pumpAndSettle();

    expect(repo.deletedWith, 'my-password');
    expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
    expect(await TokenStorage.instance.hasTokens, isFalse);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('doctor with open cases is told to contact Tera; nothing is asked or deleted', (tester) async {
    final repo = _FakeRepo(blocked: AccountDeletionBlocked('doctor_has_active_cases', 'x'));
    final container = await _pump(tester, UserRole.doctor, repo);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Account can\'t be deleted'), findsOneWidget);
    expect(find.textContaining('Contact Tera'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(repo.deletedWith, isNull);
    expect(container.read(authStateProvider), isA<AuthAuthenticated>());
  });

  testWidgets('wrong password: error shown, user stays signed in', (tester) async {
    final repo = _FakeRepo(wrongPassword: true);
    final container = await _pump(tester, UserRole.engineer, repo);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Account not deleted'), findsOneWidget);
    expect(find.text('كلمة المرور غير صحيحة.'), findsOneWidget);
    expect(container.read(authStateProvider), isA<AuthAuthenticated>());
    expect(await TokenStorage.instance.hasTokens, isTrue);
  });

  test('a message whose sender account was deleted still parses', () {
    final m = ChatMessageModel.fromJson({
      'id': 1, 'case': 7, 'sender': null, 'sender_name': 'Deleted user', 'sender_role': null,
      'inquiry_type': 'technical', 'text': 'restart it', 'created_at': '2026-10-16T10:00:00Z',
      'is_read': true, 'is_mine': false,
    });
    expect(m.senderId, isNull);
    expect(m.senderName, 'Deleted user');
  });
}
