import 'package:axon/core/attacks/attack_models.dart';
import 'package:axon/core/attacks/attack_repository.dart';
import 'package:axon/core/network/api_client.dart';
import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/features/doctor/models/case_model.dart';
import 'package:axon/features/patient/screens/attack_confirmation_prompt.dart';
import 'package:axon/features/patient/screens/log_attack_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAttackRepository extends AttackRepository {
  _FakeAttackRepository() : super(ApiClient(onSessionExpired: () {}));
  final logged = <NewAttackEventPayload>[];

  @override
  Future<AttackEventModel> logAttack(NewAttackEventPayload payload) async {
    logged.add(payload);
    return AttackEventModel(
      id: logged.length,
      caseId: payload.caseId,
      occurredAt: payload.occurredAt,
      timeIsApproximate: payload.timeIsApproximate,
      durationSeconds: payload.durationSeconds,
      severity: payload.severity,
      tookMedication: payload.tookMedication,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<AttackEventModel>> fetchAttacks(int caseId) async => const [];
}

CaseModel _case(DiagnosisType diagnosis, {DateTime? createdAt, CaseStatus status = CaseStatus.inTreatment}) =>
    CaseModel(
      id: 7,
      patientId: 1,
      patientName: 'p',
      deviceSetupParameters: const {},
      diagnosisType: diagnosis,
      status: status,
      initialEvaluation: '',
      treatmentPlan: '',
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );

AttackLogConfirmationModel _confirmed(DateTime at) =>
    AttackLogConfirmationModel(id: 1, caseId: 7, hadUnlogged: false, confirmedAt: at);

Future<_FakeAttackRepository> _openDialog(WidgetTester tester, CaseModel myCase) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _FakeAttackRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [attackRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showLogAttackDialog(context, myCase),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);

  group('shouldAskAttackConfirmation', () {
    final today = DateTime.utc(2026, 10, 14);

    test('asks when never confirmed and case is at least a week old', () {
      expect(shouldAskAttackConfirmation(myCase: _case(DiagnosisType.migraine), confirmations: const [], today: today),
          isTrue);
    });

    test('does not ask for a new or closed case', () {
      final newCase = _case(DiagnosisType.migraine, createdAt: fromBaghdadWallTime(2026, 10, 10, 12));
      expect(shouldAskAttackConfirmation(myCase: newCase, confirmations: const [], today: today), isFalse);
      final closed = _case(DiagnosisType.migraine, status: CaseStatus.closed);
      expect(shouldAskAttackConfirmation(myCase: closed, confirmations: const [], today: today), isFalse);
    });

    test('waits 7 days after a confirmation or a local dismissal', () {
      final c = _case(DiagnosisType.migraine);
      expect(
        shouldAskAttackConfirmation(
            myCase: c, confirmations: [_confirmed(fromBaghdadWallTime(2026, 10, 8, 9))], today: today),
        isFalse,
      );
      expect(
        shouldAskAttackConfirmation(
            myCase: c, confirmations: [_confirmed(fromBaghdadWallTime(2026, 10, 7, 9))], today: today),
        isTrue,
      );
      expect(
        shouldAskAttackConfirmation(
            myCase: c, confirmations: const [], dismissedDay: DateTime.utc(2026, 10, 12), today: today),
        isFalse,
      );
    });
  });

  testWidgets('migraine: approximate time, hours+minutes, severity and medication', (tester) async {
    final repo = await _openDialog(tester, _case(DiagnosisType.migraine));
    expect(find.text('ما شدة النوبة؟ (1 خفيفة – 10 شديدة جداً)'), findsOneWidget);

    await _tapText(tester, 'أمس');
    await _tapText(tester, 'وقت تقريبي');
    await tester.pump();
    await _tapText(tester, 'مساءً');
    await tester.enterText(find.widgetWithText(TextField, 'ساعات'), '3');
    await tester.enterText(find.widgetWithText(TextField, 'دقائق'), '30');
    await _tapText(tester, '7');
    await _tapText(tester, 'نعم');
    await _tapText(tester, 'حفظ');
    await tester.pumpAndSettle();

    expect(repo.logged, hasLength(1));
    final p = repo.logged.single;
    expect(p.durationSeconds, 3 * 3600 + 30 * 60);
    expect(p.severity, 7);
    expect(p.tookMedication, isTrue);
    expect(p.timeIsApproximate, isTrue);
    final yesterday = baghdadToday().subtract(const Duration(days: 1));
    expect(toBaghdad(p.occurredAt), DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 18));
    expect(p.toJson().containsKey('severity'), isTrue);

    // "log another" resets the form for the next missed attack
    expect(find.text('تسجيل نوبة أخرى'), findsOneWidget);
    await _tapText(tester, 'تسجيل نوبة أخرى');
    await tester.pumpAndSettle();
    expect(find.text('حفظ'), findsOneWidget);
  });

  testWidgets('epilepsy: no severity question, minutes+seconds, severity never sent', (tester) async {
    final repo = await _openDialog(tester, _case(DiagnosisType.epilepsy));
    expect(find.textContaining('ما شدة النوبة'), findsNothing);

    await _tapText(tester, 'أمس');
    await _tapText(tester, 'وقت تقريبي');
    await tester.pump();
    await _tapText(tester, 'صباحاً');
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'صباحاً')).selected, isTrue);
    await tester.enterText(find.widgetWithText(TextField, 'دقائق'), '1');
    await tester.enterText(find.widgetWithText(TextField, 'ثوانٍ'), '45');
    await _tapText(tester, 'لا');
    await _tapText(tester, 'حفظ');
    await tester.pumpAndSettle();

    final p = repo.logged.single;
    expect(p.durationSeconds, 105);
    expect(p.severity, isNull);
    expect(p.tookMedication, isFalse);
    expect(p.toJson().containsKey('severity'), isFalse);
  });

  testWidgets('medication answer is required before saving', (tester) async {
    final repo = await _openDialog(tester, _case(DiagnosisType.epilepsy));
    await _tapText(tester, 'أمس');
    await _tapText(tester, 'وقت تقريبي');
    await tester.pump();
    await _tapText(tester, 'ظهراً');
    await tester.enterText(find.widgetWithText(TextField, 'ثوانٍ'), '50');
    await _tapText(tester, 'حفظ');
    await tester.pump();
    expect(repo.logged, isEmpty);
    expect(find.text('أجب: هل أخذت دواء للنوبة؟'), findsOneWidget);
  });
}

/// Scrolls the dialog to the widget first — chips can sit below the fold
/// on a phone-size screen.
Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
}
