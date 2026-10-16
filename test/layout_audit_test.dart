import 'package:axon/core/attacks/attack_models.dart';
import 'package:axon/core/attacks/attack_repository.dart';
import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/user_model.dart';
import 'package:axon/core/network/api_client.dart';
import 'package:axon/core/permissions/user_role.dart';
import 'package:axon/core/time/baghdad_time.dart';
import 'package:axon/features/attack_stats/attack_statistics_screen.dart';
import 'package:axon/features/auth/login_screen.dart';
import 'package:axon/features/chat/data/chat_repository.dart';
import 'package:axon/features/chat/data/engineer_conversation_model.dart';
import 'package:axon/features/chat/logic/chat_notifier.dart';
import 'package:axon/features/doctor/doctor_providers.dart' as doctor;
import 'package:axon/features/doctor/models/case_model.dart';
import 'package:axon/features/doctor/models/device_model.dart';
import 'package:axon/features/doctor/models/patient_model.dart';
import 'package:axon/features/doctor/screens/add_case_screen.dart';
import 'package:axon/features/doctor/screens/add_patient_dialog.dart';
import 'package:axon/features/doctor/screens/case_details_screen.dart';
import 'package:axon/features/doctor/screens/doctor_home_screen.dart';
import 'package:axon/features/engineer/engineer_providers.dart' as engineer;
import 'package:axon/features/engineer/models/case_summary_model.dart';
import 'package:axon/features/engineer/models/clinic_model.dart';
import 'package:axon/features/engineer/models/device_type_model.dart';
import 'package:axon/features/engineer/models/doctor_model.dart';
import 'package:axon/features/engineer/models/engineer_device_model.dart';
import 'package:axon/features/engineer/models/engineer_model.dart';
import 'package:axon/features/engineer/screens/add_clinic_dialog.dart';
import 'package:axon/features/engineer/screens/add_device_screen.dart';
import 'package:axon/features/engineer/screens/add_device_type_dialog.dart';
import 'package:axon/features/engineer/screens/device_details_screen.dart';
import 'package:axon/features/engineer/screens/engineer_home_screen.dart';
import 'package:axon/features/engineer/screens/engineer_patient_details_screen.dart';
import 'package:axon/features/patient/models/session_model.dart';
import 'package:axon/features/patient/patient_providers.dart';
import 'package:axon/features/patient/screens/log_attack_dialog.dart';
import 'package:axon/features/patient/screens/patient_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_audit.dart';

// ---------------------------------------------------------------- fixtures

final _now = DateTime.now();
DateTime _daysAgo(int d, [int hour = 12]) {
  final day = baghdadToday().subtract(Duration(days: d));
  return fromBaghdadWallTime(day.year, day.month, day.day, hour);
}

CaseModel _case(DiagnosisType diagnosis, {CaseStatus status = CaseStatus.inTreatment}) => CaseModel(
      id: 7,
      patientId: 1,
      patientName: 'Abdulrahman Mohammed Al-Husseini',
      doctorName: 'Dr. Zainab Abdulkareem',
      deviceId: 'dev-1',
      deviceTypeName: 'Neurostimulator Model A',
      deviceSerialNumber: 'SN-2026-000042',
      clinicName: 'Al-Kindy Teaching Hospital Neurology Clinic',
      deviceSetupParameters: const {},
      diagnosisType: diagnosis,
      diseaseType: diagnosis == DiagnosisType.migraine ? 'with_aura' : 'combined',
      status: status,
      monthlyEpisodeCount: 12,
      episodeDurationMinutes: 300,
      symptoms: 'Throbbing headache, nausea, sensitivity to light',
      currentMedications: 'Topiramate 50 mg, Sumatriptan as needed',
      totalSessionsPlanned: 30,
      completedSessionsCount: 12,
      remainingSessionsCount: 18,
      initialEvaluation: 'Frequent attacks for three years',
      treatmentPlan: 'Daily 20-minute sessions for six weeks',
      createdAt: _daysAgo(60),
      updatedAt: _now,
    );

final _sessions = [
  for (final d in [40, 30, 20, 10, 3])
    SessionModel(
      id: d,
      caseId: 7,
      performedByName: '',
      sessionDate: _daysAgo(d, 9),
      durationMinutes: 20,
      deviceParameters: const {},
      doctorNotes: '',
      patientResponse: 'ممتاز',
      createdAt: _daysAgo(d, 9),
    ),
];

List<AttackEventModel> _attacks(bool migraine) => [
      for (final (i, d) in [50, 25, 12, 9, 2, 1].indexed)
        AttackEventModel(
          id: i + 1,
          caseId: 7,
          occurredAt: _daysAgo(d, 8 + i),
          timeIsApproximate: i.isEven,
          durationSeconds: migraine ? (2 + i) * 3600 + 20 * 60 : 60 + i * 15,
          severity: migraine ? 3 + i : null,
          tookMedication: i.isOdd,
          createdAt: _daysAgo(d - (i == 3 ? 2 : 0), 20),
        ),
    ];

final _confirmations = [
  AttackLogConfirmationModel(id: 1, caseId: 7, hadUnlogged: false, confirmedAt: _daysAgo(8)),
  AttackLogConfirmationModel(id: 2, caseId: 7, hadUnlogged: true, confirmedAt: _daysAgo(1)),
];

final _deviceJson = {
  'id': 'dev-1',
  'serial_number': 'SN-2026-000042',
  'device_type': 1,
  'device_type_name': 'Neurostimulator Model A',
  'clinic': 1,
  'clinic_name': 'Al-Kindy Teaching Hospital Neurology Clinic',
  'status': 'active',
  'installed_at': '2026-01-15',
  'last_maintenance_at': '2026-09-01',
  'created_at': '2026-01-10T10:00:00Z',
  'updated_at': '2026-09-01T10:00:00Z',
};

final _clinic = ClinicModel.fromJson({
  'id': 1,
  'name': 'Al-Kindy Teaching Hospital Neurology Clinic',
  'address': 'Baghdad, Al-Mansour district',
  'phone_number': '07701234567',
  'contact_person': 'Dr. Haider Al-Saadi',
  'responsible_engineer': 3,
});

final _deviceType = DeviceTypeModel.fromJson({
  'id': 1,
  'name': 'Neurostimulator Model A',
  'description': 'Transcutaneous stimulation device for migraine and epilepsy',
  'setup_schema': <String, dynamic>{},
  'is_active': true,
});

final _conversation = EngineerConversationModel.fromJson({
  'case': 7,
  'patient_name': 'Abdulrahman Mohammed Al-Husseini',
  'device_serial': 'SN-2026-000042',
  'clinic_name': 'Al-Kindy Teaching Hospital Neurology Clinic',
  'responsible_engineer': 3,
  'responsible_engineer_name': 'Eng. Mustafa Kareem',
  'case_status': 'in_treatment',
  'last_message_text': 'The device stopped after five minutes, what should I do?',
  'last_message_at': _now.toUtc().toIso8601String(),
  'unread_count': 3,
  'can_reply': true,
});

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._status);
  final AuthStatus _status;
  @override
  AuthStatus build() => _status;
}

AuthStatus _signedIn(UserRole role) => AuthAuthenticated(
      UserModel(id: 1, username: 'ahmed.kareem88', email: 'x@example.com', role: role),
    );

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(ApiClient(onSessionExpired: () {}));
  @override
  Future<InboxPage> getEngineerInbox({required int page, required bool mine}) async =>
      InboxPage([_conversation], false);
}

List<Override> _common(UserRole role, CaseModel c, {bool migraine = true}) => [
      authStateProvider.overrideWith(() => _FakeAuth(_signedIn(role))),
      unreadByCaseProvider.overrideWith((ref) => Stream.value({7: 2})),
      caseAttacksProvider.overrideWith((ref, id) async => _attacks(migraine)),
      caseAttackConfirmationsProvider.overrideWith((ref, id) async => _confirmations),
      // doctor
      doctor.myCasesProvider.overrideWith((ref) async => [c]),
      doctor.caseSessionsProvider.overrideWith((ref, id) async => _sessions),
      doctor.patientsListProvider.overrideWith((ref) async => [
            PatientModel.fromJson({'id': 1, 'username': 'patient_one', 'full_name': c.patientName}),
          ]),
      doctor.devicesListProvider.overrideWith((ref, _) async => [
            DeviceModel.fromJson({..._deviceJson, 'is_available': true}),
          ]),
      // engineer
      engineer.engineerCaseSessionsProvider.overrideWith((ref, id) async => _sessions),
      engineer.allCasesProvider.overrideWith((ref) async => [c]),
      engineer.allPatientsProvider.overrideWith((ref) async => [
            PatientModel.fromJson({'id': 1, 'username': 'patient_one', 'full_name': c.patientName}),
          ]),
      engineer.doctorsListProvider.overrideWith((ref) async => [
            DoctorModel.fromJson({'id': 2, 'username': 'dr_zainab', 'full_name': 'Dr. Zainab Abdulkareem', 'specialty': 'Neurology'}),
          ]),
      engineer.engineersListProvider.overrideWith((ref) async => [
            EngineerModel.fromJson({'id': 3, 'username': 'eng_mustafa', 'full_name': 'Eng. Mustafa Kareem'}),
          ]),
      engineer.clinicsListProvider.overrideWith((ref) async => [_clinic]),
      engineer.deviceTypesListProvider.overrideWith((ref) async => [_deviceType]),
      engineer.devicesListProvider.overrideWith((ref) async => [EngineerDeviceModel.fromJson(_deviceJson)]),
      engineer.casesForDeviceProvider.overrideWith((ref, id) async => [
            CaseSummaryModel.fromJson({
              'id': 7,
              'patient_name': c.patientName,
              'doctor_name': c.doctorName,
              'diagnosis_type': c.diagnosisType.apiValue,
              'status': 'in_treatment',
              'completed_sessions_count': 12,
              'created_at': '2026-08-01T10:00:00Z',
            }),
          ]),
      chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
      // patient
      myCaseProvider.overrideWith((ref) async => c),
      mySessionsProvider.overrideWith((ref) async => _sessions),
    ];

/// A screen whose only content is a button that opens a dialog.
Widget _opener(Future<void> Function(BuildContext context, WidgetRef ref) open) => Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(child: TextButton(onPressed: () => open(context, ref), child: const Text('open'))),
      ),
    );

Future<void> _tapOpen(WidgetTester tester) => tester.tap(find.text('open'));

// ---------------------------------------------------------------- audit

final _found = <String, List<LayoutProblem>>{};

Future<void> _audit(
  WidgetTester tester,
  String name,
  Widget screen,
  List<Override> overrides, {
  Future<void> Function(WidgetTester tester)? interact,
  bool arabic = false,
  Set<String> allow = const {},
}) async {
  await loadAuditFonts();
  if (arabic && !arabicFontAvailable) {
    markTestSkipped('No Arabic-capable font found for "$name"');
    return;
  }
  final problems = await auditScreen(tester, screen, overrides: overrides, interact: interact, allow: allow);
  _found[name] = problems;
  expect(problems, isEmpty, reason: '$name at ${phoneWidth.toInt()} dp, text x$textScale:\n  ${problems.join('\n  ')}');
}

void main() {
  final migraine = _case(DiagnosisType.migraine);
  final epilepsy = _case(DiagnosisType.epilepsy);

  group('patient (Arabic)', () {
    testWidgets('home', (t) => _audit(t, 'patient home', const PatientHomeScreen(),
        _common(UserRole.patient, migraine), arabic: true));
    testWidgets('home — calendar month picker', (t) => _audit(t, 'patient calendar picker',
        const PatientHomeScreen(), _common(UserRole.patient, migraine),
        interact: (t) async {
          final title = find.byIcon(Icons.arrow_drop_down);
          await t.ensureVisible(title);
          await t.tap(title);
          await t.pumpAndSettle();
          expect(find.text('تشرين الثاني'), findsOneWidget, reason: 'month picker did not open');
        }, arabic: true));
    testWidgets('log attack — migraine', (t) => _audit(t, 'log attack migraine',
        _opener((context, ref) => showLogAttackDialog(context, migraine)), _common(UserRole.patient, migraine),
        interact: (t) async {
          await _tapOpen(t);
          await t.pumpAndSettle();
          await t.tap(find.text('وقت تقريبي'));
        }, arabic: true));
    testWidgets('log attack — epilepsy', (t) => _audit(t, 'log attack epilepsy',
        _opener((context, ref) => showLogAttackDialog(context, epilepsy)), _common(UserRole.patient, epilepsy),
        interact: _tapOpen, arabic: true));
  });

  group('doctor', () {
    testWidgets('login', (t) => _audit(t, 'login', const LoginScreen(),
        [authStateProvider.overrideWith(() => _FakeAuth(const AuthUnauthenticated()))], arabic: true));
    testWidgets('home', (t) => _audit(t, 'doctor home', const DoctorHomeScreen(), _common(UserRole.doctor, migraine)));
    testWidgets('case details', (t) => _audit(t, 'case details', CaseDetailsScreen(caseModel: migraine),
        _common(UserRole.doctor, migraine)));
    testWidgets('case details — calendar month picker', (t) => _audit(t, 'doctor calendar picker',
        CaseDetailsScreen(caseModel: migraine), _common(UserRole.doctor, migraine),
        interact: (t) async {
          final title = find.byIcon(Icons.arrow_drop_down).last;
          await t.ensureVisible(title);
          await t.tap(title);
          await t.pumpAndSettle();
          expect(find.text('September'), findsOneWidget, reason: 'month picker did not open');
        }));
    testWidgets('add case', (t) => _audit(t, 'add case', const AddCaseScreen(), _common(UserRole.doctor, migraine)));
    testWidgets('add patient dialog', (t) => _audit(t, 'add patient dialog',
        _opener((context, ref) => showAddPatientDialog(context, ref)), _common(UserRole.doctor, migraine),
        interact: _tapOpen));
    for (final g in ['Weekly', 'Monthly', 'Yearly']) {
      testWidgets('attack statistics — $g', (t) => _audit(t, 'attack statistics $g',
          AttackStatisticsScreen(caseModel: migraine, sessionsProvider: doctor.caseSessionsProvider(7)),
          _common(UserRole.doctor, migraine), interact: (t) async {
            await t.ensureVisible(find.text(g));
            await t.pumpAndSettle();
            await t.tap(find.text(g));
          }));
    }
    testWidgets('attack statistics — all time', (t) => _audit(t, 'attack statistics all time',
        AttackStatisticsScreen(caseModel: migraine, sessionsProvider: doctor.caseSessionsProvider(7)),
        _common(UserRole.doctor, migraine), interact: (t) => t.tap(find.text('All time'))));
    testWidgets('case details — edit case sheet', (t) => _audit(t, 'doctor edit case sheet',
        CaseDetailsScreen(caseModel: migraine), _common(UserRole.doctor, migraine),
        interact: (t) async {
          await t.tap(find.byTooltip('Edit case'));
          await t.pumpAndSettle();
          expect(find.text('Save Changes'), findsOneWidget, reason: 'edit sheet did not open');
        }));
  });

  group('engineer', () {
    // tab label -> a text only that tab shows (proves the tab really opened)
    const tabs = {
      'Overview': 'Unlinked devices',
      'Messages': 'The device stopped after five minutes, what should I do?',
      'Devices': 'SN-2026-000042',
      'Clinics': 'Dr. Haider Al-Saadi',
      'Device Types': 'Transcutaneous stimulation device for migraine and epilepsy',
    };
    for (final MapEntry(key: tab, value: marker) in tabs.entries) {
      testWidgets('home — $tab', (t) => _audit(t, 'engineer $tab', const EngineerHomeScreen(),
          _common(UserRole.engineer, migraine),
          // The inbox shows the last message as a deliberate 2-line preview;
          // the full text is in the chat.
          allow: {'The device stopped after five minutes, what should I do?'},
          interact: (t) async {
            final tabLabel = find.descendant(of: find.byType(TabBar), matching: find.text(tab));
            await t.ensureVisible(tabLabel);
            await t.tap(tabLabel);
            await t.pumpAndSettle();
            expect(find.textContaining(marker), findsWidgets, reason: 'tab "$tab" did not open');
          }));
    }
    testWidgets('patient details', (t) => _audit(t, 'engineer patient details',
        EngineerPatientDetailsScreen(caseModel: epilepsy), _common(UserRole.engineer, epilepsy, migraine: false)));
    testWidgets('device details', (t) => _audit(t, 'device details',
        DeviceDetailsScreen(device: EngineerDeviceModel.fromJson(_deviceJson)), _common(UserRole.engineer, migraine)));
    testWidgets('add device', (t) => _audit(t, 'add device', const AddDeviceScreen(), _common(UserRole.engineer, migraine)));
    testWidgets('add clinic dialog', (t) => _audit(t, 'add clinic dialog',
        _opener((context, ref) => showAddClinicDialog(context)), _common(UserRole.engineer, migraine),
        interact: _tapOpen));
    testWidgets('add device type dialog', (t) => _audit(t, 'add device type dialog',
        _opener((context, ref) => showAddDeviceTypeDialog(context)), _common(UserRole.engineer, migraine),
        interact: _tapOpen));
  });
}
