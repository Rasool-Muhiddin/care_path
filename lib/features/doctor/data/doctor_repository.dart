import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../patient/models/session_model.dart';
import '../models/case_model.dart';
import '../models/case_progress_note_model.dart';
import '../models/device_model.dart';
import '../models/patient_model.dart';

/// طبقة التواصل مع بيانات الطبيب: حالاته، قائمة المرضى (لاختيار مريض
/// عند إنشاء حالة)، قائمة الأجهزة (لاختيار جهاز)، وإنشاء حالة جديدة.
class DoctorRepository {
  DoctorRepository(this._client);
  final ApiClient _client;

  List<T> _extractList<T>(dynamic data, T Function(Map<String, dynamic>) fromJson) {
    final results = data is Map && data.containsKey('results') ? data['results'] as List : data as List;
    return results.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  /// حالات الطبيب الحالي فقط (الفلترة تلقائية من الـ backend عبر get_queryset)
  Future<List<CaseModel>> fetchMyCases() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.cases);
      return _extractList(response.data, CaseModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// كل المرضى المسجلين بالنظام — لاختيار المريض عند إنشاء حالة جديدة
  Future<List<PatientModel>> fetchPatients() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.patients);
      return _extractList(response.data, PatientModel.fromJson);
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
      final response = await _client.raw.get(
        ApiEndpoints.devices,
        queryParameters: {
          if (availableOnly) 'available': 'true',
          if (excludeCaseId != null) 'exclude_case': excludeCaseId,
        },
      );
      return _extractList(response.data, DeviceModel.fromJson);
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
      final response = await _client.raw.get(
        ApiEndpoints.sessions,
        queryParameters: {'case': caseId},
      );
      return _extractList(response.data, SessionModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// ملاحظات تطور حالة معيّنة (الأحدث أولاً — ordering من الـ backend)
  Future<List<CaseProgressNoteModel>> fetchProgressNotes(int caseId) async {
    try {
      final response = await _client.raw.get(
        ApiEndpoints.caseProgressNotes,
        queryParameters: {'case': caseId},
      );
      return _extractList(response.data, CaseProgressNoteModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// إضافة ملاحظة تطور جديدة لحالة — اللقطات (عدد الجلسات وقتها) تُحسب
  /// تلقائياً بالـ backend، لا نرسلها من هنا
  Future<CaseProgressNoteModel> createProgressNote(NewCaseProgressNotePayload payload) async {
    try {
      final response =
          await _client.raw.post(ApiEndpoints.caseProgressNotes, data: payload.toJson());
      return CaseProgressNoteModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}