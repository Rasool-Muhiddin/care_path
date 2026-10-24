import 'package:axon/core/attacks/attack_models.dart';
import 'package:axon/core/attacks/attack_repository.dart';
import 'package:axon/core/attacks/attack_stats.dart';
import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/features/attack_stats/attack_statistics_screen.dart';
import 'package:axon/features/doctor/models/case_model.dart';
import 'package:axon/features/patient/models/session_model.dart';
import 'package:axon/core/widgets/sessions_vs_attacks_chart.dart';
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
  createdAt: _daysAgo(150),
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
  testWidgets('statistics screen defaults to the last 3 months and has no lists', (tester) async {
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
    expect(find.text('Attack log'), findsNothing);
    // Baseline 8 / month, shown per selected period (weekly = 8 × 12 / 52).
    expect(find.text('Baseline (before treatment): 1.85 / week'), findsOneWidget);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('Baseline (before treatment): 8 / month'), findsOneWidget);

    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 attacks'), findsOneWidget);
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    expect(find.text('Baseline (before treatment): 96 / year'), findsOneWidget);
  });

  test('baseline converts the monthly rate per period and is hidden when unknown', () {
    expect(SessionsVsAttacksChart.baselineFor(4, StatsGranularity.weekly), closeTo(0.923, 0.001));
    expect(SessionsVsAttacksChart.baselineFor(4, StatsGranularity.monthly), 4);
    expect(SessionsVsAttacksChart.baselineFor(4, StatsGranularity.yearly), 48);
    expect(SessionsVsAttacksChart.baselineFor(null, StatsGranularity.monthly), isNull);
    expect(SessionsVsAttacksChart.baselineFor(0, StatsGranularity.monthly), isNull);
  });

  test('monthly/weekly axis labels put the year on a second line only when it changes', () {
    final analysis = AttackAnalysis(
      caseCreatedAt: DateTime.utc(2025, 11, 1),
      sessions: const [],
      attacks: const [],
      confirmations: const [],
      today: DateTime.utc(2026, 3, 15),
    );
    final months = analysis.periods(DateTime.utc(2025, 11, 1), DateTime.utc(2026, 3, 16), StatsGranularity.monthly);
    expect(
      [for (var i = 0; i < months.length; i++) SessionsVsAttacksChart.periodLabel(months, i, StatsGranularity.monthly)],
      ['Nov\n2025', 'Dec', 'Jan\n2026', 'Feb', 'Mar'],
    );
    final weeks = analysis.periods(DateTime.utc(2025, 12, 20), DateTime.utc(2026, 1, 10), StatsGranularity.weekly);
    final weekLabels = [
      for (var i = 0; i < weeks.length; i++) SessionsVsAttacksChart.periodLabel(weeks, i, StatsGranularity.weekly),
    ];
    expect(weekLabels.first, endsWith('\n2025'));
    expect(weekLabels.where((l) => l.contains('\n2026')), hasLength(1));
  });

  testWidgets('no baseline line or legend when the case has no before-treatment count', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionsVsAttacksChart(
          periods: AttackAnalysis(
            caseCreatedAt: DateTime.utc(2026, 1, 1),
            sessions: const [],
            attacks: const [],
            confirmations: const [],
            today: DateTime.utc(2026, 3, 15),
          ).periods(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 3, 16), StatsGranularity.monthly),
          granularity: StatsGranularity.monthly,
        ),
      ),
    ));
    expect(find.textContaining('Baseline'), findsNothing);
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
