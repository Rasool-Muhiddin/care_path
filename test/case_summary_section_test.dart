import 'package:axon/core/attacks/attack_models.dart';
import 'package:axon/core/attacks/attack_repository.dart';
import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/features/case_summary/case_summary_section.dart';
import 'package:axon/features/doctor/models/case_model.dart';
import 'package:axon/features/patient/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CaseModel _case(DiagnosisType diagnosis) => CaseModel(
      id: 7,
      patientId: 1,
      patientName: 'Sara',
      doctorName: 'Dr. Ali',
      deviceTypeName: 'Type A',
      deviceSerialNumber: 'SN-42',
      clinicName: 'Baghdad Clinic',
      deviceSetupParameters: const {},
      diagnosisType: diagnosis,
      status: CaseStatus.inTreatment,
      monthlyEpisodeCount: 8,
      episodeDurationMinutes: 240,
      symptoms: 'Aura, nausea',
      currentMedications: 'Topiramate',
      totalSessionsPlanned: 20,
      completedSessionsCount: 5,
      remainingSessionsCount: 15,
      initialEvaluation: '',
      treatmentPlan: 'Daily 20 min',
      guarantorName: 'Omar',
      createdAt: fromBaghdadWallTime(2026, 9, 1, 10),
      updatedAt: fromBaghdadWallTime(2026, 10, 1, 10),
    );

final _sessions = FutureProvider.autoDispose<List<SessionModel>>((ref) async => [
      SessionModel(
        id: 1,
        caseId: 7,
        performedByName: '',
        sessionDate: fromBaghdadWallTime(2026, 9, 10, 9),
        deviceParameters: const {},
        doctorNotes: '',
        patientResponse: '',
        createdAt: fromBaghdadWallTime(2026, 9, 10, 9),
      ),
    ]);

Future<void> _pump(WidgetTester tester, CaseModel c, List<AttackEventModel> attacks) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [caseAttacksProvider(7).overrideWith((ref) async => attacks)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: CaseSummarySection(caseModel: c, sessionsProvider: _sessions)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

AttackEventModel _attackToday({int? severity, int seconds = 2 * 3600}) => AttackEventModel(
      id: 1,
      caseId: 7,
      occurredAt: DateTime.now().subtract(const Duration(minutes: 5)),
      timeIsApproximate: false,
      durationSeconds: seconds,
      severity: severity,
      tookMedication: false,
      createdAt: DateTime.now(),
    );

void main() {
  testWidgets('migraine: before-treatment and current parts with Average labels', (tester) async {
    await _pump(tester, _case(DiagnosisType.migraine), [_attackToday(severity: 7)]);

    expect(find.text('Before treatment'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Average attacks / month'), findsOneWidget);
    expect(find.text('Average attack duration'), findsNWidgets(2)); // baseline + this month
    expect(find.text('4 h'), findsOneWidget);
    expect(find.text('Average severity'), findsOneWidget);
    expect(find.text('7.0 / 10'), findsOneWidget);
    expect(find.text('Topiramate'), findsOneWidget);
    expect(find.text('2026/09/10'), findsOneWidget); // treatment start = first session
    expect(find.text('5 of 20 (15 remaining)'), findsOneWidget);
    expect(find.text('SN-42'), findsOneWidget);
    expect(find.text('Baghdad Clinic'), findsOneWidget);
    expect(find.text('Omar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('epilepsy: no severity row', (tester) async {
    await _pump(tester, _case(DiagnosisType.epilepsy), [_attackToday(seconds: 90)]);
    expect(find.text('Average severity'), findsNothing);
    expect(find.text('1 min 30 s'), findsOneWidget);
  });
}
