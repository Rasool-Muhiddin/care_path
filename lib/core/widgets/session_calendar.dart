import 'package:flutter/material.dart';

import '../../features/patient/models/session_model.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';

/// Baghdad is UTC+3 all year (no DST since 2008). Session days are grouped
/// by this fixed offset — not the device timezone — so the calendar agrees
/// with the backend's "one session per Baghdad calendar day" rule even when
/// the phone is set to another zone.
const Duration _baghdadOffset = Duration(hours: 3);

/// Wall-clock time in Baghdad for [t], as a UTC-flagged [DateTime] whose
/// fields (year/month/day/hour/minute) are the Baghdad values.
DateTime toBaghdad(DateTime t) => t.toUtc().add(_baghdadOffset);

/// Integer key (yyyymmdd) for the Baghdad calendar day of [t].
int _dayKey(DateTime baghdad) => baghdad.year * 10000 + baghdad.month * 100 + baghdad.day;

String _two(int n) => n.toString().padLeft(2, '0');

/// UI strings for [SessionCalendar]. Weekday names start on Saturday
/// (the local week start in Iraq).
class SessionCalendarStrings {
  const SessionCalendarStrings({
    required this.monthNames,
    required this.weekdayNames,
    required this.legendSession,
    required this.legendNoSession,
    required this.sessionsInMonth,
    required this.durationLabel,
    required this.timeLabel,
    required this.feedbackLabel,
    required this.today,
  });

  final List<String> monthNames;
  final List<String> weekdayNames;
  final String legendSession;
  final String legendNoSession;
  final String Function(int count) sessionsInMonth;
  final String Function(int minutes) durationLabel;
  final String timeLabel;
  final String feedbackLabel;
  final String today;

  static final en = SessionCalendarStrings(
    monthNames: const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ],
    weekdayNames: const ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
    legendSession: 'Session day',
    legendNoSession: 'No session',
    sessionsInMonth: (n) => '$n ${n == 1 ? 'session' : 'sessions'} this month',
    durationLabel: (m) => 'Duration: $m min',
    timeLabel: 'Time',
    feedbackLabel: 'Patient feedback',
    today: 'Today',
  );

  static final ar = SessionCalendarStrings(
    monthNames: const [
      'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
      'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
    ],
    weekdayNames: const ['سبت', 'أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'],
    legendSession: 'يوم جلسة',
    legendNoSession: 'بدون جلسة',
    sessionsInMonth: (n) => 'عدد الجلسات هذا الشهر: $n',
    durationLabel: (m) => 'المدة: $m دقيقة',
    timeLabel: 'الوقت',
    feedbackLabel: 'التقييم',
    today: 'اليوم',
  );
}

/// Monthly calendar of a case's treatment sessions, shared by the doctor's
/// case details screen (English, LTR) and the patient's home screen
/// (Arabic, RTL). Layout direction follows the ambient [Directionality].
///
/// Session days are highlighted; tapping one shows that day's session(s)
/// below the grid. Tapping the month title opens a month/year picker.
class SessionCalendar extends StatefulWidget {
  const SessionCalendar({
    super.key,
    required this.sessions,
    required this.strings,
    this.accent = AppAccent.patient,
  });

  final List<SessionModel> sessions;
  final SessionCalendarStrings strings;
  final Color accent;

  @override
  State<SessionCalendar> createState() => _SessionCalendarState();
}

class _SessionCalendarState extends State<SessionCalendar> {
  late int _year;
  late int _month;
  int? _selectedKey;
  bool _picking = false;
  late int _pickerYear;
  late Map<int, List<SessionModel>> _byDay;

  @override
  void initState() {
    super.initState();
    final today = toBaghdad(DateTime.now());
    _year = today.year;
    _month = today.month;
    _pickerYear = _year;
    _byDay = _group(widget.sessions);
  }

  @override
  void didUpdateWidget(SessionCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _byDay = _group(widget.sessions);
      if (_selectedKey != null && !_byDay.containsKey(_selectedKey)) _selectedKey = null;
    }
  }

  static Map<int, List<SessionModel>> _group(List<SessionModel> sessions) {
    final map = <int, List<SessionModel>>{};
    for (final s in sessions) {
      (map[_dayKey(toBaghdad(s.sessionDate))] ??= []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.sessionDate.compareTo(b.sessionDate));
    }
    return map;
  }

  void _shiftMonth(int delta) {
    setState(() {
      final m = DateTime.utc(_year, _month + delta);
      _year = m.year;
      _month = m.month;
      _selectedKey = null;
    });
  }

  void _goTo(int year, int month) {
    setState(() {
      _year = year;
      _month = month;
      _selectedKey = null;
      _picking = false;
    });
  }

  int get _sessionsInVisibleMonth {
    final from = _year * 10000 + _month * 100;
    var count = 0;
    _byDay.forEach((key, list) {
      if (key > from && key < from + 100) count += list.length;
    });
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final selected = _selectedKey != null ? _byDay[_selectedKey] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassContainer(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 6),
              if (_picking) _monthYearPicker() else _grid(),
              const SizedBox(height: 10),
              _legend(),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          _DayDetails(dayKey: _selectedKey!, sessions: selected, strings: s, accent: widget.accent),
        ],
      ],
    );
  }

  Widget _header() {
    final s = widget.strings;
    // chevron_left/right mirror automatically under RTL, so "previous"
    // always points toward the start edge.
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: _picking ? () => setState(() => _pickerYear--) : () => _shiftMonth(-1),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _picking = !_picking;
              _pickerYear = _year;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _picking ? '$_pickerYear' : '${s.monthNames[_month - 1]} $_year',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_picking ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white),
          onPressed: _picking ? () => setState(() => _pickerYear++) : () => _shiftMonth(1),
        ),
      ],
    );
  }

  Widget _monthYearPicker() {
    final s = widget.strings;
    final today = toBaghdad(DateTime.now());
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var m = 1; m <= 12; m++)
              _PickerCell(
                label: s.monthNames[m - 1],
                isCurrent: _pickerYear == _year && m == _month,
                hasSessions: _byDay.keys.any((k) => k ~/ 100 == _pickerYear * 100 + m),
                accent: widget.accent,
                onTap: () => _goTo(_pickerYear, m),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => _goTo(today.year, today.month),
          icon: const Icon(Icons.today_outlined, size: 18),
          label: Text(s.today),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ],
    );
  }

  Widget _grid() {
    final s = widget.strings;
    final today = toBaghdad(DateTime.now());
    final todayKey = _dayKey(today);
    final daysInMonth = DateTime.utc(_year, _month + 1, 0).day;
    // DateTime.weekday: Mon=1..Sun=7. Columns start on Saturday.
    final leading = (DateTime.utc(_year, _month, 1).weekday + 1) % 7;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;

    final rows = <Widget>[
      Row(
        children: [
          for (final name in s.weekdayNames)
            Expanded(
              child: Center(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
    ];

    for (var start = 0; start < cellCount; start += 7) {
      rows.add(Row(
        children: [
          for (var i = start; i < start + 7; i++)
            Expanded(child: _cell(i - leading + 1, daysInMonth, todayKey)),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _cell(int day, int daysInMonth, int todayKey) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 40);
    final key = _year * 10000 + _month * 100 + day;
    final count = _byDay[key]?.length ?? 0;
    final hasSession = count > 0;
    final isSelected = key == _selectedKey;
    final isToday = key == todayKey;
    final accent = widget.accent;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasSession ? () => setState(() => _selectedKey = isSelected ? null : key) : null,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: hasSession ? accent.withValues(alpha: isSelected ? 0.85 : 0.45) : null,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: Colors.white, width: 1.6)
                : isToday
                    ? Border.all(color: Colors.white54)
                    : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  color: hasSession ? Colors.white : Colors.white70,
                  fontWeight: hasSession || isToday ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              // Backend allows one session per day; if older data has more,
              // flag the count instead of hiding it.
              if (count > 1)
                PositionedDirectional(
                  top: 1,
                  end: 3,
                  child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend() {
    final s = widget.strings;
    Widget swatch(Color? fill, {bool outlined = false}) => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: outlined ? Border.all(color: Colors.white38) : null,
          ),
        );
    const legendText = TextStyle(color: Colors.white70, fontSize: 12);

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          swatch(widget.accent.withValues(alpha: 0.45)),
          const SizedBox(width: 6),
          Text(s.legendSession, style: legendText),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          swatch(null, outlined: true),
          const SizedBox(width: 6),
          Text(s.legendNoSession, style: legendText),
        ]),
        if (!_picking)
          Text(
            s.sessionsInMonth(_sessionsInVisibleMonth),
            style: TextStyle(color: widget.accent, fontSize: 12, fontWeight: FontWeight.w700),
          ),
      ],
    );
  }
}

class _PickerCell extends StatelessWidget {
  const _PickerCell({
    required this.label,
    required this.isCurrent,
    required this.hasSessions,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final bool hasSessions;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isCurrent ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasSessions ? accent.withValues(alpha: 0.7) : Colors.white12),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Details for the session(s) on the selected day: date, time, duration
/// (only when recorded) and the patient's old feedback (only when present).
class _DayDetails extends StatelessWidget {
  const _DayDetails({
    required this.dayKey,
    required this.sessions,
    required this.strings,
    required this.accent,
  });

  final int dayKey;
  final List<SessionModel> sessions;
  final SessionCalendarStrings strings;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${dayKey ~/ 10000}/${_two(dayKey ~/ 100 % 100)}/${_two(dayKey % 100)}';
    const hint = TextStyle(color: Colors.white60, fontSize: 12.5);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(dateLabel, style: AppText.tileTitle),
            ],
          ),
          for (final session in sessions) ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final t = toBaghdad(session.sessionDate);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${strings.timeLabel}: ${_two(t.hour)}:${_two(t.minute)}', style: hint),
                  if (session.durationMinutes != null)
                    Text(strings.durationLabel(session.durationMinutes!), style: hint),
                  if (session.patientResponse.isNotEmpty)
                    Text(
                      '${strings.feedbackLabel}: ${session.patientResponse}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}
