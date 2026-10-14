import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/core/widgets/session_calendar.dart';
import 'package:axon/features/patient/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionModel _session(int id, DateTime utc, {int? minutes, String response = ''}) => SessionModel(
      id: id,
      caseId: 1,
      performedByName: '',
      sessionDate: utc.toLocal(),
      durationMinutes: minutes,
      deviceParameters: const {},
      doctorNotes: '',
      patientResponse: response,
      createdAt: utc.toLocal(),
    );

Widget _host(List<SessionModel> sessions, SessionCalendarStrings strings, TextDirection dir) => MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: SingleChildScrollView(child: SessionCalendar(sessions: sessions, strings: strings)),
        ),
      ),
    );

void main() {
  final today = toBaghdad(DateTime.now());
  // 10th of the current Baghdad month, 22:30 UTC = 01:30 on the 11th in Baghdad.
  final lateNightUtc = DateTime.utc(today.year, today.month, 10, 22, 30);

  testWidgets('groups by Baghdad day, counts the month, shows details on tap', (tester) async {
    await tester.pumpWidget(_host(
      [
        _session(1, lateNightUtc, minutes: 20, response: 'ممتاز'),
        _session(2, DateTime.utc(today.year, today.month, 3, 9), minutes: null),
        // Previous month — must not be counted.
        _session(3, DateTime.utc(today.year, today.month - 1, 15, 9)),
      ],
      SessionCalendarStrings.en,
      TextDirection.ltr,
    ));

    expect(find.text('2 sessions this month'), findsOneWidget);

    await tester.tap(find.text('11'));
    await tester.pump();
    expect(find.text('Time: 01:30'), findsOneWidget);
    expect(find.text('Duration: 20 min'), findsOneWidget);
    expect(find.text('Patient feedback: ممتاز'), findsOneWidget);

    // The 10th has no session in Baghdad time, so tapping it shows nothing.
    await tester.tap(find.text('10'));
    await tester.pump();
    expect(find.textContaining('Time:'), findsOneWidget);

    // Session without duration/feedback shows only the time.
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('Time: 12:00'), findsOneWidget);
    expect(find.textContaining('Duration'), findsNothing);
    expect(find.textContaining('feedback'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('1 session this month'), findsOneWidget);
  });

  test('isBaghdadToday uses the Baghdad day, not the device day', () {
    final nowBaghdad = toBaghdad(DateTime.now());
    // Baghdad midnight starting today, expressed in UTC (21:00 UTC the day before).
    final startOfToday = DateTime.utc(nowBaghdad.year, nowBaghdad.month, nowBaghdad.day)
        .subtract(const Duration(hours: 3));
    expect(isBaghdadToday(startOfToday), isTrue);
    expect(isBaghdadToday(startOfToday.subtract(const Duration(minutes: 1))), isFalse);
    expect(isBaghdadToday(startOfToday.add(const Duration(hours: 23, minutes: 59))), isTrue);
    expect(isBaghdadToday(startOfToday.add(const Duration(hours: 24))), isFalse);
  });

  testWidgets('month/year picker jumps to another year', (tester) async {
    await tester.pumpWidget(_host(const [], SessionCalendarStrings.ar, TextDirection.rtl));
    expect(find.text('عدد الجلسات هذا الشهر: 0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('${today.year - 1}'), findsOneWidget);

    await tester.tap(find.text('شباط'));
    await tester.pump();
    expect(find.text('شباط ${today.year - 1}'), findsOneWidget);
  });
}
