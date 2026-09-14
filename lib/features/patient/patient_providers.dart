import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../doctor/models/case_model.dart' show CaseModel;
import 'data/patient_repository.dart';
import 'models/session_model.dart';

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository(ref.read(apiClientProvider));
});

/// يجلب جلسات المريض الحالي، ويعيد الجلب تلقائياً إذا تغيّرت حالة المصادقة
/// (مفيد بعد تسجيل خروج/دخول متتالٍ بنفس جلسة التطبيق)
final mySessionsProvider = FutureProvider.autoDispose<List<SessionModel>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(patientRepositoryProvider).fetchMySessions();
});

/// حالة المريض الحالية — لعرض خطة العلاج ونوع الجهاز بأعلى الشاشة الرئيسية
final myCaseProvider = FutureProvider.autoDispose<CaseModel?>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(patientRepositoryProvider).fetchMyCase();
});