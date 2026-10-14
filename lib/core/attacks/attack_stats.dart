import '../../features/patient/models/session_model.dart';
import '../time/baghdad_time.dart';
import 'attack_models.dart';

/// Per-period attack statistics, computed on the device from the full
/// attack/session/confirmation lists (they're small — a few hundred rows
/// per case per year). All grouping is by Baghdad calendar day, the same
/// day boundary as the session calendar and the backend.
///
/// "Baseline (before treatment)" and "During treatment" never mix: the
/// treatment period starts on the Baghdad day of the first treatment
/// session; attacks logged before that day belong to the baseline.

enum StatsGranularity { weekly, monthly, yearly }

DateTime periodStartOf(DateTime day, StatsGranularity g) => switch (g) {
      StatsGranularity.weekly => saturdayWeekStart(day),
      StatsGranularity.monthly => DateTime.utc(day.year, day.month),
      StatsGranularity.yearly => DateTime.utc(day.year),
    };

DateTime nextPeriodStart(DateTime start, StatsGranularity g) => switch (g) {
      StatsGranularity.weekly => start.add(const Duration(days: 7)),
      StatsGranularity.monthly => DateTime.utc(start.year, start.month + 1),
      StatsGranularity.yearly => DateTime.utc(start.year + 1),
    };

/// Whether the patient confirmed they had no unlogged attacks over a
/// period's past days.
enum ConfirmationStatus {
  /// No fully past day in the period yet (e.g. the current week's first day).
  inProgress,
  confirmed,
  partial,
  unconfirmed,
}

class PeriodStats {
  PeriodStats._({
    required this.start,
    required this.end,
    required this.sessions,
    required this.attacks,
    required this.pastDays,
    required this.confirmedDays,
  });

  /// Baghdad days, [start, end).
  final DateTime start;
  final DateTime end;
  final int sessions;
  final List<AttackEventModel> attacks;

  /// Days of the period (inside the analysed range) that are fully past.
  final int pastDays;

  /// Of [pastDays], how many are covered by a "no unlogged attacks" confirmation.
  final int confirmedDays;

  int get attackCount => attacks.length;

  int? get minDurationSeconds =>
      attacks.isEmpty ? null : attacks.map((a) => a.durationSeconds).reduce((a, b) => a < b ? a : b);
  int? get maxDurationSeconds =>
      attacks.isEmpty ? null : attacks.map((a) => a.durationSeconds).reduce((a, b) => a > b ? a : b);
  double? get avgDurationSeconds =>
      attacks.isEmpty ? null : attacks.fold<int>(0, (s, a) => s + a.durationSeconds) / attacks.length;

  /// Average over attacks that have a severity (migraine). Null if none.
  double? get avgSeverity {
    final rated = attacks.where((a) => a.severity != null).toList();
    if (rated.isEmpty) return null;
    return rated.fold<int>(0, (s, a) => s + a.severity!) / rated.length;
  }

  int get medicatedCount => attacks.where((a) => a.tookMedication).length;
  double? get medicatedShare => attacks.isEmpty ? null : medicatedCount / attacks.length;
  int get lateCount => attacks.where((a) => a.isLateLogged).length;
  int get approximateCount => attacks.where((a) => a.timeIsApproximate).length;

  ConfirmationStatus get confirmation {
    if (pastDays == 0) return ConfirmationStatus.inProgress;
    if (confirmedDays >= pastDays) return ConfirmationStatus.confirmed;
    if (confirmedDays == 0) return ConfirmationStatus.unconfirmed;
    return ConfirmationStatus.partial;
  }

  /// Zero attacks that the patient hasn't confirmed — must not be shown
  /// as a clean zero.
  bool get isUnconfirmedZero => attackCount == 0 && confirmation != ConfirmationStatus.confirmed;
}

class AttackAnalysis {
  AttackAnalysis({
    required DateTime caseCreatedAt,
    required List<SessionModel> sessions,
    required List<AttackEventModel> attacks,
    required List<AttackLogConfirmationModel> confirmations,
    DateTime? today,
  })  : today = today ?? baghdadToday(),
        _sessionDays = sessions.map((s) => baghdadDayOf(s.sessionDate)).toList(),
        _attacks = [...attacks]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt)) {
    var start = baghdadDayOf(caseCreatedAt);
    if (_attacks.isNotEmpty) {
      final firstAttackDay = baghdadDayOf(_attacks.first.occurredAt);
      if (firstAttackDay.isBefore(start)) start = firstAttackDay;
    }
    caseStartDay = start;
    treatmentStartDay = _sessionDays.isEmpty ? null : _sessionDays.reduce((a, b) => a.isBefore(b) ? a : b);
    for (final c in confirmations) {
      final day = baghdadDayOf(c.confirmedAt);
      for (var i = 1; i <= AttackLogConfirmationModel.coveredDays; i++) {
        _coveredDays.add(day.subtract(Duration(days: i)));
      }
    }
  }

  /// Today's Baghdad day (injectable for tests).
  final DateTime today;
  late final DateTime caseStartDay;

  /// Baghdad day of the first treatment session; null = treatment not started.
  late final DateTime? treatmentStartDay;

  final List<DateTime> _sessionDays;
  final List<AttackEventModel> _attacks;
  final Set<DateTime> _coveredDays = {};

  List<AttackEventModel> get attacksNewestFirst => _attacks.reversed.toList();

  /// Everything before the treatment period (all of it if there's no
  /// session yet).
  PeriodStats baseline() =>
      _summarize(caseStartDay, treatmentStartDay ?? today.add(const Duration(days: 1)));

  /// During-treatment periods from the first session up to today, oldest
  /// first, including periods with zero attacks. Empty before treatment.
  List<PeriodStats> treatmentPeriods(StatsGranularity g) {
    final start = treatmentStartDay;
    if (start == null) return const [];
    final periods = <PeriodStats>[];
    for (var p = periodStartOf(start, g); !p.isAfter(today); p = nextPeriodStart(p, g)) {
      periods.add(_summarize(p, nextPeriodStart(p, g), rangeStart: start));
    }
    return periods;
  }

  /// A calendar month (any phase) — for the summary card's
  /// this-month-vs-last-month comparison.
  PeriodStats calendarMonth(int monthsAgo) {
    final start = DateTime.utc(today.year, today.month - monthsAgo);
    return _summarize(start, DateTime.utc(start.year, start.month + 1));
  }

  PeriodStats _summarize(DateTime start, DateTime end, {DateTime? rangeStart}) {
    final from = rangeStart != null && rangeStart.isAfter(start) ? rangeStart : start;
    bool inRange(DateTime day) => !day.isBefore(from) && day.isBefore(end);

    var pastDays = 0;
    var confirmedDays = 0;
    for (var d = from; d.isBefore(end) && d.isBefore(today); d = d.add(const Duration(days: 1))) {
      pastDays++;
      if (_coveredDays.contains(d)) confirmedDays++;
    }

    return PeriodStats._(
      start: start,
      end: end,
      sessions: _sessionDays.where(inRange).length,
      attacks: _attacks.where((a) => inRange(baghdadDayOf(a.occurredAt))).toList(),
      pastDays: pastDays,
      confirmedDays: confirmedDays,
    );
  }
}

/// The doctor's "attacks per month before treatment" baseline, scaled to
/// a period length so it can be drawn as a reference line on any view.
double? baselineForGranularity(int? monthlyAttacks, StatsGranularity g) {
  if (monthlyAttacks == null) return null;
  return switch (g) {
    StatsGranularity.weekly => monthlyAttacks * 7 / 30.44,
    StatsGranularity.monthly => monthlyAttacks.toDouble(),
    StatsGranularity.yearly => monthlyAttacks * 12.0,
  };
}

/// "3 h 20 min", "1 min 45 s", "45 s" (English) or the Arabic equivalent.
String formatAttackDuration(num seconds, {bool arabic = false}) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final parts = <String>[];
  if (arabic) {
    if (h > 0) parts.add('$h ساعة');
    if (m > 0) parts.add('$m دقيقة');
    if (s > 0 && h == 0) parts.add('$s ثانية');
    return parts.isEmpty ? '0 ثانية' : parts.join(' و');
  }
  if (h > 0) parts.add('$h h');
  if (m > 0) parts.add('$m min');
  if (s > 0 && h == 0) parts.add('$s s');
  return parts.isEmpty ? '0 s' : parts.join(' ');
}
