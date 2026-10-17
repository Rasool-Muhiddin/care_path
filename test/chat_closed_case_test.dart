import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/user_model.dart';
import 'package:axon/core/network/api_client.dart';
import 'package:axon/core/permissions/user_role.dart';
import 'package:axon/features/chat/data/chat_message_model.dart';
import 'package:axon/features/chat/data/chat_repository.dart';
import 'package:axon/features/chat/data/engineer_conversation_model.dart';
import 'package:axon/features/chat/presentation/chat_screen.dart';
import 'package:axon/features/doctor/models/case_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._status);
  final AuthStatus _status;
  @override
  AuthStatus build() => _status;
}

/// يرجع رسالة نصية واحدة، وحالة الحالة كما يرسلها الخادم في X-Case-Status
/// (null = بلا header). [caseStatus] قابل للتغيير لمحاكاة إغلاق الحالة.
class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository(this.caseStatus) : super(ApiClient(onSessionExpired: () {}));

  CaseStatus? caseStatus;

  @override
  Future<ChatPage> getMessages(int caseId, InquiryType inquiryType, {int? afterId, int? beforeId}) async {
    final messages = afterId != null || beforeId != null
        ? <ChatMessageModel>[]
        : [
            ChatMessageModel.fromJson({
              'id': 1,
              'case': caseId,
              'sender': 99,
              'sender_name': 'Other',
              'inquiry_type': inquiryType.apiValue,
              'kind': 'text',
              'text': 'earlier message',
              'created_at': '2026-10-17T10:00:00Z',
              'is_read': true,
              'is_mine': false,
            }),
          ];
    return ChatPage(messages, caseStatus);
  }

  @override
  Future<ReplyRights> getReplyRights(int caseId) async => const ReplyRights(canReply: true);
}

const _patientNotice = 'هذه الحالة مغلقة، لا يمكن إرسال رسائل جديدة';
const _staffNotice = "This case is closed — new messages can't be sent.";

Future<void> _openChat(
  WidgetTester tester, {
  required UserRole role,
  required _FakeChatRepository repo,
  CaseStatus? initialCaseStatus,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _FakeAuth(AuthAuthenticated(UserModel(
            id: 1,
            username: 'user',
            email: '',
            role: role,
          )))),
      chatRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: ChatScreen(caseId: 5, initialCaseStatus: initialCaseStatus)),
  ));
  await tester.pump();
  // المريض يختار القناة أولاً
  if (role == UserRole.patient) {
    await tester.tap(find.text(InquiryType.medical.arabicLabel));
  }
  await tester.pump();
  await tester.pump();
  expect(find.text('earlier message'), findsOneWidget, reason: 'reading always works');
}

/// يفكّك الشاشة كي يتوقف مؤقّت الـ polling قبل نهاية الاختبار.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void _expectInputShown() {
  expect(find.byType(TextField), findsOneWidget);
  expect(find.byIcon(Icons.mic), findsOneWidget);
  expect(find.text(_patientNotice), findsNothing);
  expect(find.text(_staffNotice), findsNothing);
}

void _expectInputHidden(String notice) {
  expect(find.byType(TextField), findsNothing);
  expect(find.byIcon(Icons.mic), findsNothing);
  expect(find.byIcon(Icons.send), findsNothing);
  expect(find.text(notice), findsOneWidget);
}

void main() {
  for (final role in [UserRole.patient, UserRole.doctor, UserRole.engineer]) {
    final notice = role == UserRole.patient ? _patientNotice : _staffNotice;

    testWidgets('${role.name}: open case shows the input with mic', (tester) async {
      await _openChat(tester, role: role, repo: _FakeChatRepository(CaseStatus.inTreatment));
      _expectInputShown();
      await _close(tester);
    });

    testWidgets('${role.name}: closed case (from server) hides the input', (tester) async {
      await _openChat(tester, role: role, repo: _FakeChatRepository(CaseStatus.closed));
      _expectInputHidden(notice);
      await _close(tester);
    });
  }

  testWidgets('closed status passed in by the caller hides the input before the server answers',
      (tester) async {
    await _openChat(
      tester,
      role: UserRole.engineer,
      repo: _FakeChatRepository(null),
      initialCaseStatus: CaseStatus.closed,
    );
    _expectInputHidden(_staffNotice);
    await _close(tester);
  });

  testWidgets('server status wins over a stale status passed in', (tester) async {
    await _openChat(
      tester,
      role: UserRole.doctor,
      repo: _FakeChatRepository(CaseStatus.inTreatment),
      initialCaseStatus: CaseStatus.closed,
    );
    _expectInputShown();
    await _close(tester);
  });

  testWidgets('case closed while the chat is open switches to the notice on the next refresh',
      (tester) async {
    final repo = _FakeChatRepository(CaseStatus.inTreatment);
    await _openChat(tester, role: UserRole.patient, repo: repo);
    _expectInputShown();

    repo.caseStatus = CaseStatus.closed;
    // دورة الـ polling التالية (كل 8 ثوانٍ)
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    _expectInputHidden(_patientNotice);
    await _close(tester);
  });
}
