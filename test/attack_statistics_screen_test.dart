import 'package:axon/core/attacks/attack_models.dart';
import 'package:axon/core/attacks/attack_repository.dart';
import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/features/attack_stats/attack_statistics_screen.dart';
import 'package:axon/features/doctor/models/case_model.dart';
import 'package:axon/features/patient/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.now();
final _today = baghdadToday();
DateTime _daysAgo(int days, [int hour = 12]) {
  final d = _today.subtract(Duration(days: days));
  return fromBaghdadWallTime(d.year, d.month, d.day, hour);
}

final _case = CaseModel(
  id: 7,
  patientId: 1,
  patientName: 'Sara',
  deviceSetupParameters: const {},
  diagnosisType: DiagnosisType.migraine,
  status: CaseStatus.inTreatment,
  monthlyEpisodeCount: 8,
  episodeDurationMinutes: 240,
  initialEvaluation: '',
  treatmentPlan: '',
  createdAt: _daysAgo(60),
  updatedAt: _now,
);

final _sessions = [
  for (final d in [40, 39, 38])
    SessionModel(
      id: d,
      caseId: 7,
      performedByName: '',
      sessionDate: _daysAgo(d),
      deviceParameters: const {},
      doctorNotes: '',
      patientResponse: '',
      createdAt: _daysAgo(d),
    ),
];

AttackEventModel _attack(int id, int daysAgo, {int severity = 6, bool medication = false}) => AttackEventModel(
      id: id,
      caseId: 7,
      occurredAt: _daysAgo(daysAgo),
      timeIsApproximate: false,
      durationSeconds: 3 * 3600,
      severity: severity,
      tookMedication: medication,
      createdAt: _daysAgo(daysAgo, 15),
    );

final _testSessionsProvider = FutureProvider.autoDispose<List<SessionModel>>((ref) async => _sessions);

Widget _app(Widget child) => ProviderScope(
      overrides: [
        caseAttacksProvider(7).overrideWith((ref) async => [
              _attack(1, 50), // before the first session -> baseline
              _attack(2, 2, severity: 4, medication: true),
              _attack(3, 1, severity: 8),
            ]),
        caseAttackConfirmationsProvider(7).overrideWith((ref) async => const <AttackLogConfirmationModel>[]),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('statistics screen separates baseline from treatment and switches to yearly', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      AttackStatisticsScreen(caseModel: _case, sessionsProvider: _testSessionsProvider),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Baseline (before treatment)'), findsWidgets); // section + chart legend
    expect(find.text('During treatment'), findsOneWidget);
    expect(find.text('Attack log'), findsOneWidget);
    expect(find.text('3 attacks logged in total'), findsOneWidget);

    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    // Treatment-period years only contain the 2 attacks after the first session
    // (skipped on Jan 1-2, when those two attacks fall in different years).
    if (_daysAgo(2).year == _today.year) {
      expect(find.text('2 attacks'), findsWidgets);
      expect(find.text('1 of 2 (50%)'), findsWidgets);
      expect(find.text('6.0 / 10'), findsWidgets);
    }
  });

  testWidgets('statistics screen lays out at phone size without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      AttackStatisticsScreen(caseModel: _case, sessionsProvider: _testSessionsProvider),
    ));
    await tester.pumpAndSettle();
    for (final view in ['Weekly', 'Monthly', 'Yearly']) {
      await tester.tap(find.text(view));
      await tester.pumpAndSettle();
    }
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary card shows this month vs last month and opens the screen', (tester) async {
    await tester.pumpWidget(_app(
      SingleChildScrollView(child: AttackSummaryCard(caseModel: _case, sessionsProvider: _testSessionsProvider)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);

    await tester.tap(find.text('View detailed statistics'));
    await tester.pumpAndSettle();
    expect(find.byType(AttackStatisticsScreen), findsOneWidget);
  });
}
