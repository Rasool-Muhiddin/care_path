import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../patient/models/session_model.dart';
import '../models/case_model.dart';
import '../models/device_model.dart';
import '../models/patient_model.dart';

/// طبقة التواصل مع بيانات الطبيب: حالاته، قائمة المرضى (لاختيار مريض
/// عند إنشاء حالة)، قائمة الأجهزة (لاختيار جهاز)، وإنشاء حالة جديدة.
class DoctorRepository {
  DoctorRepository(this._client);
  final ApiClient _client;

  /// حالات الطبيب الحالي فقط (الفلترة تلقائية من الـ backend عبر get_queryset)
  Future<List<CaseModel>> fetchMyCases() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.cases);
      return items.map(CaseModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// كل المرضى المسجلين بالنظام — لاختيار المريض عند إنشاء حالة جديدة
  Future<List<PatientModel>> fetchPatients() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.patients);
      return items.map(PatientModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// الأجهزة لاختيار الجهاز عند إنشاء/تعديل حالة.
  /// [availableOnly]: إذا true يستثني أي جهاز مرتبط فعلياً بأي حالة أخرى
  /// (جهاز واحد لكل مريض). [excludeCaseId]: عند تعديل حالة موجودة، يبقي
  /// جهاز تلك الحالة نفسها ضمن القائمة رغم كونه "مرتبطاً" بها.
  Future<List<DeviceModel>> fetchDevices({
    bool availableOnly = false,
    int? excludeCaseId,
  }) async {
    try {
      final items = await _client.getAllPages(
        ApiEndpoints.devices,
        queryParameters: {
          if (availableOnly) 'available': 'true',
          if (excludeCaseId != null) 'exclude_case': excludeCaseId,
        },
      );
      return items.map(DeviceModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<CaseModel> createCase(NewCasePayload payload) async {
    try {
      final response = await _client.raw.post(ApiEndpoints.cases, data: payload.toJson());
      return CaseModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// تحديث حالة موجودة (الحالة، خطة العلاج، التقييم الأولي)
  Future<CaseModel> updateCase(int caseId, CaseUpdatePayload payload) async {
    try {
      final response = await _client.raw.patch(
        '${ApiEndpoints.cases}$caseId/',
        data: payload.toJson(),
      );
      return CaseModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// جلسات حالة معيّنة — لعرض تاريخ الجلسات بشاشة تفاصيل الحالة
  Future<List<SessionModel>> fetchSessionsForCase(int caseId) async {
    try {
      final items = await _client.getAllPages(
        ApiEndpoints.sessions,
        queryParameters: {'case': caseId},
      );
      return items.map(SessionModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
