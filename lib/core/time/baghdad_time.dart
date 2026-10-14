/// Baghdad time helpers — the single source of truth for "which day" a
/// timestamp belongs to across the app (session calendar, attack stats,
/// daily-session check, attack logging). Baghdad is UTC+3 all year (no
/// DST since 2008), matching the backend's TIME_ZONE='Asia/Baghdad', so a
/// fixed offset is exact and independent of the phone's timezone.
library;

const Duration baghdadOffset = Duration(hours: 3);

/// Wall-clock time in Baghdad for [t], as a UTC-flagged [DateTime] whose
/// fields (year/month/day/hour/minute) are the Baghdad values.
DateTime toBaghdad(DateTime t) => t.toUtc().add(baghdadOffset);

/// The Baghdad calendar day of [t], as a UTC-flagged midnight (y, m, d).
/// Day values compare and subtract cleanly (no DST, no local zone).
DateTime baghdadDayOf(DateTime t) {
  final b = toBaghdad(t);
  return DateTime.utc(b.year, b.month, b.day);
}

/// Today's Baghdad calendar day.
DateTime baghdadToday() => baghdadDayOf(DateTime.now());

/// Whether [t] falls on today's Baghdad calendar day — the same day
/// boundary the backend uses for its one-session-per-day rule.
bool isBaghdadToday(DateTime t) => baghdadDayOf(t) == baghdadToday();

/// The real instant for a Baghdad wall-clock time (returned in UTC).
DateTime fromBaghdadWallTime(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(baghdadOffset);

/// Saturday that starts the week containing [day] (local week start in
/// Iraq; also the first column of the session calendar).
DateTime saturdayWeekStart(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).subtract(Duration(days: (day.weekday + 1) % 7));
