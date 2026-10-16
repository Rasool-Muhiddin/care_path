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
              _attack(1, 120), // outside the default 3-month window
              _attack(2, 2, severity: 4, medication: true),
              _attack(3, 1, severity: 8),
            ]),
        caseAttackConfirmationsProvider(7).overrideWith((ref) async => const <AttackLogConfirmationModel>[]),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('statistics screen defaults to the last 3 months and has no baseline or lists', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      AttackStatisticsScreen(caseModel: _case, sessionsProvider: _testSessionsProvider),
    ));
    await tester.pumpAndSettle();

    // Last 3 months: only the 2 recent attacks.
    expect(find.text('Last 3 months'), findsOneWidget);
    expect(find.text('Attacks'), findsWidgets);
    expect(find.text('Sessions vs attacks'), findsOneWidget);
    expect(find.text('1 of 2 attacks'), findsOneWidget);
    expect(find.text('6.0 / 10'), findsOneWidget);
    expect(find.textContaining('Baseline'), findsNothing);
    expect(find.text('Attack log'), findsNothing);

    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 attacks'), findsOneWidget);
  });

  testWidgets('statistics screen lays out at phone size without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      AttackStatisticsScreen(caseModel: _case, sessionsProvider: _testSessionsProvider),
    ));
    await tester.pumpAndSettle();
    for (final period in ['This year', 'All time', 'Last 3 months']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      for (final view in ['Weekly', 'Monthly', 'Yearly']) {
        await tester.ensureVisible(find.text(view));
        await tester.pumpAndSettle();
        await tester.tap(find.text(view), warnIfMissed: false); // disabled segments ignore the tap
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
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
