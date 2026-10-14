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
      patientResponse: '',
      createdAt: when,
    );

var _id = 0;
AttackEventModel attack(
  DateTime when, {
  int seconds = 3600,
  int? severity,
  bool medication = false,
  bool approximate = false,
  DateTime? loggedAt,
}) =>
    AttackEventModel(
      id: ++_id,
      caseId: 1,
      occurredAt: when,
      timeIsApproximate: approximate,
      durationSeconds: seconds,
      severity: severity,
      tookMedication: medication,
      createdAt: loggedAt ?? when.add(const Duration(hours: 1)),
    );

AttackLogConfirmationModel confirmation(DateTime when) =>
    AttackLogConfirmationModel(id: ++_id, caseId: 1, hadUnlogged: false, confirmedAt: when);

void main() {
  test('baseline and treatment never mix; treatment starts at first session', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(9, 1),
      sessions: [session(at(9, 20)), session(at(10, 1))],
      attacks: [attack(at(9, 5)), attack(at(9, 19)), attack(at(9, 20)), attack(at(10, 2))],
      confirmations: const [],
      today: today,
    );
    expect(a.treatmentStartDay, DateTime.utc(2026, 9, 20));
    expect(a.baseline().attackCount, 2);

    final months = a.treatmentPeriods(StatsGranularity.monthly);
    expect(months.map((p) => p.start), [DateTime.utc(2026, 9), DateTime.utc(2026, 10)]);
    // September during treatment = 20th onwards only.
    expect(months[0].attackCount, 1);
    expect(months[0].sessions, 1);
    expect(months[1].attackCount, 1);
  });

  test('no session yet: everything is baseline, no treatment periods', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(10, 1),
      sessions: const [],
      attacks: [attack(at(10, 3)), attack(at(10, 13))],
      confirmations: const [],
      today: today,
    );
    expect(a.treatmentStartDay, isNull);
    expect(a.baseline().attackCount, 2);
    expect(a.treatmentPeriods(StatsGranularity.weekly), isEmpty);
  });

  test('per-period duration, severity, medication, late and approximate stats', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(10, 1),
      sessions: [session(at(10, 1))],
      attacks: [
        attack(at(10, 5), seconds: 2 * 3600, severity: 4, medication: true),
        attack(at(10, 6), seconds: 5 * 3600, severity: 8, approximate: true,
            loggedAt: at(10, 8)),
        attack(at(10, 7), seconds: 3 * 3600, severity: 6),
      ],
      confirmations: const [],
      today: today,
    );
    final october = a.treatmentPeriods(StatsGranularity.monthly).single;
    expect(october.attackCount, 3);
    expect(october.minDurationSeconds, 2 * 3600);
    expect(october.maxDurationSeconds, 5 * 3600);
    expect(october.avgDurationSeconds, 10 * 3600 / 3);
    expect(october.avgSeverity, 6);
    expect(october.medicatedCount, 1);
    expect(october.medicatedShare, closeTo(1 / 3, 1e-9));
    expect(october.lateCount, 1);
    expect(october.approximateCount, 1);
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
    final weeks = a.treatmentPeriods(StatsGranularity.weekly);
    expect(weeks.last.start, DateTime.utc(2026, 10, 10));
    expect(weeks.last.attackCount, 1);
    expect(weeks[weeks.length - 2].attackCount, 0);
  });

  test('a zero week is unconfirmed unless covered by a confirmation', () {
    final a = AttackAnalysis(
      caseCreatedAt: at(9, 1),
      sessions: [session(at(9, 1))],
      attacks: const [],
      // Confirmed on Sat 10-10: covers Sat 10-03 .. Fri 10-09 (the whole previous week).
      confirmations: [confirmation(at(10, 10, 9))],
      today: today,
    );
    final weeks = a.treatmentPeriods(StatsGranularity.weekly);
    final previous = weeks.firstWhere((w) => w.start == DateTime.utc(2026, 10, 3));
    final older = weeks.firstWhere((w) => w.start == DateTime.utc(2026, 9, 26));
    final current = weeks.last; // Sat 10-10 .. today (Wed): 4 past days, none covered

    expect(previous.confirmation, ConfirmationStatus.confirmed);
    expect(previous.isUnconfirmedZero, isFalse);
    expect(older.confirmation, ConfirmationStatus.unconfirmed);
    expect(older.isUnconfirmedZero, isTrue);
    expect(current.pastDays, 4);
    expect(current.confirmation, ConfirmationStatus.unconfirmed);
  });

  test('yearly view and month comparison', () {
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
    final years = a.treatmentPeriods(StatsGranularity.yearly);
    expect(years.map((y) => y.start.year), [2025, 2026]);
    expect(years.map((y) => y.attackCount), [1, 3]);
    expect(a.calendarMonth(0).attackCount, 2);
    expect(a.calendarMonth(1).attackCount, 1);
  });

  test('baseline line scales per granularity, duration formatting', () {
    expect(baselineForGranularity(null, StatsGranularity.monthly), isNull);
    expect(baselineForGranularity(10, StatsGranularity.yearly), 120);
    expect(baselineForGranularity(10, StatsGranularity.weekly), closeTo(2.3, 0.01));
    expect(formatAttackDuration(3 * 3600 + 20 * 60), '3 h 20 min');
    expect(formatAttackDuration(105), '1 min 45 s');
    expect(formatAttackDuration(105, arabic: true), '1 دقيقة و45 ثانية');
  });
}
