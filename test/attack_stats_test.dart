import 'package:axon/core/attacks/attack_models.dart';
import 'package:axon/core/attacks/attack_stats.dart';
import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/features/patient/models/session_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixed "today": Wednesday 2026-10-14 (Baghdad). Week starts Saturday 10-10.
final today = DateTime.utc(2026, 10, 14);

DateTime at(int month, int day, [int hour = 12]) => fromBaghdadWallTime(2026, month, day, hour);

SessionModel session(DateTime when) => SessionModel(
      id: when.millisecondsSinceEpoch,
      caseId: 1,
      performedByName: '',
      sessionDate: when,
      deviceParameters: const {},
      doctorNotes: '',
      createdAt: when,
    );

var _id = 0;
AttackEventModel attack(
  DateTime when, {
  int seconds = 3600,
  int? severity,
  bool medication = false,
}) =>
    AttackEventModel(
      id: ++_id,
      caseId: 1,
      occurredAt: when,
      timeIsApproximate: false,
      durationSeconds: seconds,
      severity: severity,
      tookMedication: medication,
      createdAt: when.add(const Duration(hours: 1)),
    );

AttackLogConfirmationModel confirmation(DateTime when) =>
    AttackLogConfirmationModel(id: ++_id, caseId: 1, hadUnlogged: false, confirmedAt: when);

final tomorrow = today.add(const Duration(days: 1));

void main() {
  test('range summary counts attacks and sessions of every phase inside the range', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(9, 1),
      sessions: [session(at(9, 20)), session(at(10, 1))],
      attacks: [attack(at(9, 5)), attack(at(9, 19)), attack(at(9, 20)), attack(at(10, 2))],
      confirmations: const [],
      today: today,
    );
    // Treatment starts on the case creation day, not the first session.
    expect(a.treatmentStartDay, DateTime.utc(2026, 9, 1));
    expect(a.summarize(a.treatmentStartDay, tomorrow).attackCount, 4);
    final fromSept19 = a.summarize(DateTime.utc(2026, 9, 19), DateTime.utc(2026, 10, 2));
    expect(fromSept19.attackCount, 2); // 9-19 and 9-20; 10-02 is the (exclusive) end
    expect(fromSept19.sessions, 2);
  });

  test('periods are clipped to the range and never go past today', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(9, 1),
      sessions: [session(at(9, 20)), session(at(10, 1))],
      attacks: [attack(at(9, 5)), attack(at(9, 19)), attack(at(9, 20)), attack(at(10, 2))],
      confirmations: const [],
      today: today,
    );
    final months = a.periods(DateTime.utc(2026, 9, 20), DateTime.utc(2027, 1), StatsGranularity.monthly);
    expect(months.map((p) => p.start), [DateTime.utc(2026, 9), DateTime.utc(2026, 10)]);
    // September = 20th onwards only.
    expect(months[0].attackCount, 1);
    expect(months[0].sessions, 1);
    expect(months[1].attackCount, 1);
  });

  test('summary duration, severity and medication stats', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(10, 1),
      sessions: [session(at(10, 1))],
      attacks: [
        attack(at(10, 5), seconds: 2 * 3600, severity: 4, medication: true),
        attack(at(10, 6), seconds: 5 * 3600, severity: 8),
        attack(at(10, 7), seconds: 3 * 3600, severity: 6),
      ],
      confirmations: const [],
      today: today,
    );
    final s = a.summarize(DateTime.utc(2026, 10), tomorrow);
    expect(s.attackCount, 3);
    expect(s.minDurationSeconds, 2 * 3600);
    expect(s.maxDurationSeconds, 5 * 3600);
    expect(s.avgDurationSeconds, 10 * 3600 / 3);
    expect(s.avgSeverity, 6);
    expect(s.medicatedCount, 1);
    expect(s.medicatedShare, closeTo(1 / 3, 1e-9));
  });

  test('groups by Baghdad day even when UTC is the previous day', () {
    // 00:30 Baghdad on Oct 10 (Saturday) is 21:30 UTC on Oct 9 (Friday).
    final a = AttackAnalysis(
      caseCreatedAt: at(10, 1),
      sessions: [session(at(10, 1))],
      attacks: [attack(fromBaghdadWallTime(2026, 10, 10, 0, 30))],
      confirmations: const [],
      today: today,
    );
    final weeks = a.periods(DateTime.utc(2026, 10), tomorrow, StatsGranularity.weekly);
    expect(weeks.last.start, DateTime.utc(2026, 10, 10));
    expect(weeks.last.attackCount, 1);
    expect(weeks[weeks.length - 2].attackCount, 0);
  });

  test('confirmed days count only past days covered by a confirmation', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(9, 1),
      sessions: [session(at(9, 1))],
      attacks: const [],
      // Confirmed on Sat 10-10: covers Sat 10-03 .. Fri 10-09.
      confirmations: [confirmation(at(10, 10, 9))],
      today: today,
    );
    final s = a.summarize(DateTime.utc(2026, 9, 26), tomorrow);
    expect(s.pastDays, 18); // 9-26 .. 10-13 (today isn't past)
    expect(s.confirmedDays, 7);
  });

  test('yearly periods and month comparison', () {
    final a = AttackAnalysis(
      caseCreatedAt: DateTime.utc(2025, 12, 1),
      sessions: [session(fromBaghdadWallTime(2025, 12, 1, 12))],
      attacks: [
        attack(fromBaghdadWallTime(2025, 12, 15, 12)),
        attack(at(9, 15)),
        attack(at(10, 2)),
        attack(at(10, 3)),
      ],
      confirmations: const [],
      today: today,
    );
    final years = a.periods(a.treatmentStartDay, tomorrow, StatsGranularity.yearly);
    expect(years.map((y) => y.start.year), [2025, 2026]);
    expect(years.map((y) => y.attackCount), [1, 3]);
    expect(a.calendarMonth(0).attackCount, 2);
    expect(a.calendarMonth(1).attackCount, 1);
  });

  test('auto granularity keeps multi-year ranges to a few dozen bars', () {
    final threeMonths = DateTime.utc(2026, 7, 14);
    expect(autoGranularity(threeMonths, tomorrow), StatsGranularity.weekly);
    expect(autoGranularity(DateTime.utc(2026), tomorrow), StatsGranularity.monthly);
    final threeYears = DateTime.utc(2023, 10, 14);
    expect(autoGranularity(threeYears, tomorrow), StatsGranularity.monthly);
    expect(periodCountIn(threeYears, tomorrow, StatsGranularity.monthly), lessThanOrEqualTo(maxChartPeriods));
    expect(periodCountIn(threeYears, tomorrow, StatsGranularity.weekly), greaterThan(maxChartPeriods));
    expect(autoGranularity(DateTime.utc(2020), tomorrow), StatsGranularity.yearly);
  });

  test('duration formatting', () {
    expect(formatAttackDuration(3 * 3600 + 20 * 60), '3 h 20 min');
    expect(formatAttackDuration(105), '1 min 45 s');
    expect(formatAttackDuration(105, arabic: true), '1 دقيقة و45 ثانية');
  });
}
