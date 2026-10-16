import '../../features/patient/models/session_model.dart';
import '../time/baghdad_time.dart';
import 'attack_models.dart';

/// Per-period attack statistics, computed on the device from the full
/// attack/session/confirmation lists (they're small — a few hundred rows
/// per case per year). All grouping is by Baghdad calendar day, the same
/// day boundary as the session calendar and the backend.
///
/// Everything is computed for a selected day range (see [AttackAnalysis.summarize]
/// and [AttackAnalysis.periods]); the before-treatment baseline the doctor
/// entered is shown in the case summary, not here.

enum StatsGranularity { weekly, monthly, yearly }

/// Upper bound for chart bars — a granularity that would need more periods
/// than this for the selected range isn't offered.
const int maxChartPeriods = 60;

/// Number of periods of [g] that overlap the Baghdad-day range [start, end).
int periodCountIn(DateTime start, DateTime end, StatsGranularity g) {
  var n = 0;
  for (var p = periodStartOf(start, g); p.isBefore(end); p = nextPeriodStart(p, g)) {
    n++;
  }
  return n;
}

/// A sensible default grouping for a range: weekly up to ~4 months,
/// monthly up to 3 years, yearly beyond that.
StatsGranularity autoGranularity(DateTime start, DateTime end) {
  final days = end.difference(start).inDays;
  if (days <= 120) return StatsGranularity.weekly;
  if (days <= 3 * 366) return StatsGranularity.monthly;
  return StatsGranularity.yearly;
}

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

  /// Days of the period (inside the selected range) that are fully past.
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
}

class AttackAnalysis {
  AttackAnalysis({
    required DateTime caseCreatedAt,
    required List<SessionModel> sessions,
    required List<AttackEventModel> attacks,
    required List<AttackLogConfirmationModel> confirmations,
    DateTime? today,
  })  : today = today ?? baghdadToday(),
        treatmentStartDay = baghdadDayOf(caseCreatedAt),
        _sessionDays = sessions.map((s) => baghdadDayOf(s.sessionDate)).toList(),
        _attacks = [...attacks]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt)) {
    for (final c in confirmations) {
      final day = baghdadDayOf(c.confirmedAt);
      for (var i = 1; i <= AttackLogConfirmationModel.coveredDays; i++) {
        _coveredDays.add(day.subtract(Duration(days: i)));
      }
    }
  }

  /// Today's Baghdad day (injectable for tests).
  final DateTime today;

  /// Baghdad day the case was created — treatment starts then (there's no
  /// separate start event), and it's the start of "All time". The backend
  /// rejects attacks dated before it.
  final DateTime treatmentStartDay;

  final List<DateTime> _sessionDays;
  final List<AttackEventModel> _attacks;
  final Set<DateTime> _coveredDays = {};

  /// Totals for the Baghdad-day range [start, end).
  PeriodStats summarize(DateTime start, DateTime end) => _summarize(start, end);

  /// The [g] periods overlapping [start, end), oldest first, including
  /// periods with zero attacks and never past today. Each period's numbers
  /// only count days inside the range (a range starting mid-month gives a
  /// partial first month).
  List<PeriodStats> periods(DateTime start, DateTime end, StatsGranularity g) {
    final out = <PeriodStats>[];
    for (var p = periodStartOf(start, g); p.isBefore(end) && !p.isAfter(today); p = nextPeriodStart(p, g)) {
      out.add(_summarize(p, nextPeriodStart(p, g), rangeStart: start, rangeEnd: end));
    }
    return out;
  }

  /// A calendar month (any phase) — for the summary card's
  /// this-month-vs-last-month comparison.
  PeriodStats calendarMonth(int monthsAgo) {
    final start = DateTime.utc(today.year, today.month - monthsAgo);
    return _summarize(start, DateTime.utc(start.year, start.month + 1));
  }

  PeriodStats _summarize(DateTime start, DateTime end, {DateTime? rangeStart, DateTime? rangeEnd}) {
    final from = rangeStart != null && rangeStart.isAfter(start) ? rangeStart : start;
    final to = rangeEnd != null && rangeEnd.isBefore(end) ? rangeEnd : end;
    bool inRange(DateTime day) => !day.isBefore(from) && day.isBefore(to);

    var pastDays = 0;
    var confirmedDays = 0;
    for (var d = from; d.isBefore(to) && d.isBefore(today); d = d.add(const Duration(days: 1))) {
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
