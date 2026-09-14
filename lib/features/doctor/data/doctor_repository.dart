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

  /// كل الأجهزة — لاختيار الجهاز عند إنشاء حالة جديدة
  /// (device_type_setup_schema يحدد شكل نافذة الإعدادات لكل جهاز)
  Future<List<DeviceModel>> fetchDevices() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.devices);
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
}