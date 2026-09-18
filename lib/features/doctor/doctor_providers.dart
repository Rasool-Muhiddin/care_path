import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import '../patient/models/session_model.dart';
import 'data/doctor_repository.dart';
import 'models/case_model.dart';
import 'models/device_model.dart';
import 'models/patient_model.dart';

final doctorRepositoryProvider = Provider<DoctorRepository>((ref) {
  return DoctorRepository(ref.read(apiClientProvider));
});

/// حالات الطبيب الحالي
final myCasesProvider = FutureProvider.autoDispose<List<CaseModel>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(doctorRepositoryProvider).fetchMyCases();
});

/// قائمة المرضى — تُستخدم بشاشة إنشاء حالة جديدة
final patientsListProvider = FutureProvider.autoDispose<List<PatientModel>>((ref) async {
  return ref.read(doctorRepositoryProvider).fetchPatients();
});

/// قائمة الأجهزة المتاحة — تُستخدم بشاشة إنشاء/تعديل حالة.
/// مرّر null عند إنشاء حالة جديدة، أو caseId الحالي عند تعديل حالة
/// موجودة (حتى يبقى جهازها الحالي ضمن القائمة رغم أنه "مرتبط" بها).
final devicesListProvider =
    FutureProvider.autoDispose.family<List<DeviceModel>, int?>((ref, excludeCaseId) async {
  return ref.read(doctorRepositoryProvider).fetchDevices(
        availableOnly: true,
        excludeCaseId: excludeCaseId,
      );
});

/// جلسات حالة معيّنة — لعرض تاريخ الجلسات بشاشة تفاصيل الحالة
final caseSessionsProvider =
    FutureProvider.autoDispose.family<List<SessionModel>, int>((ref, caseId) async {
  return ref.read(doctorRepositoryProvider).fetchSessionsForCase(caseId);
});