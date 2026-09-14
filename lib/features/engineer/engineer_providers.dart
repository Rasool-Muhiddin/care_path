import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import 'data/engineer_repository.dart';
import 'models/case_summary_model.dart';
import 'models/clinic_model.dart';
import 'models/device_type_model.dart';
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