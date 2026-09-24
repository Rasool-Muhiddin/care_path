import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import '../doctor/models/case_model.dart';
import '../doctor/models/patient_model.dart';
import '../doctor/models/weekly_episode_log_model.dart';
import '../patient/models/session_model.dart';
import 'data/engineer_repository.dart';
import 'models/case_summary_model.dart';
import 'models/clinic_model.dart';
import 'models/device_type_model.dart';
import 'models/doctor_model.dart';
import 'models/engineer_device_model.dart';
import 'models/engineer_model.dart';

final engineerRepositoryProvider = Provider<EngineerRepository>((ref) {
  return EngineerRepository(ref.read(apiClientProvider));
});

final devicesListProvider = FutureProvider.autoDispose<List<EngineerDeviceModel>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(engineerRepositoryProvider).fetchDevices();
});

final clinicsListProvider = FutureProvider.autoDispose<List<ClinicModel>>((ref) async {
  return ref.read(engineerRepositoryProvider).fetchClinics();
});

final deviceTypesListProvider = FutureProvider.autoDispose<List<DeviceTypeModel>>((ref) async {
  return ref.read(engineerRepositoryProvider).fetchDeviceTypes();
});

final engineersListProvider = FutureProvider.autoDispose<List<EngineerModel>>((ref) async {
  return ref.read(engineerRepositoryProvider).fetchEngineers();
});

/// كل الحالات المرتبطة بجهاز معيّن (حسب UUID تبعه) — لشاشة تفاصيل الجهاز
final casesForDeviceProvider =
    FutureProvider.autoDispose.family<List<CaseSummaryModel>, String>((ref, deviceId) async {
  return ref.read(engineerRepositoryProvider).fetchCasesForDevice(deviceId);
});

/// عدد الجلسات المسجّلة لحالة معيّنة (حسب id) — لعرض "حالة الالتزام" ببساطة
final sessionsCountForCaseProvider =
    FutureProvider.autoDispose.family<int, int>((ref, caseId) async {
  return ref.read(engineerRepositoryProvider).fetchSessionsCountForCase(caseId);
});

final doctorsListProvider = FutureProvider.autoDispose<List<DoctorModel>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(engineerRepositoryProvider).fetchDoctors();
});

final allPatientsProvider = FutureProvider.autoDispose<List<PatientModel>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(engineerRepositoryProvider).fetchPatients();
});

final allCasesProvider = FutureProvider.autoDispose<List<CaseModel>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(engineerRepositoryProvider).fetchAllCases();
});

/// جلسات حالة معيّنة (قائمة كاملة بالتواريخ) — لشارت شاشة تفاصيل المريض
final engineerCaseSessionsProvider =
    FutureProvider.autoDispose.family<List<SessionModel>, int>((ref, caseId) async {
  return ref.read(engineerRepositoryProvider).fetchSessionsForCase(caseId);
});

/// تقارير النوبات الأسبوعية لحالة معيّنة — لشارت شاشة تفاصيل المريض
final engineerCaseWeeklyEpisodeLogsProvider =
    FutureProvider.autoDispose.family<List<WeeklyEpisodeLogModel>, int>((ref, caseId) async {
  return ref.read(engineerRepositoryProvider).fetchWeeklyEpisodeLogs(caseId);
});