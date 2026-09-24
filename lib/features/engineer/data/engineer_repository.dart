import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../doctor/models/case_model.dart';
import '../../doctor/models/patient_model.dart';
import '../models/case_summary_model.dart';
import '../models/clinic_model.dart';
import '../models/device_type_model.dart';
import '../models/doctor_model.dart';
import '../models/engineer_device_model.dart';
import '../models/engineer_model.dart';

/// طبقة التواصل مع بيانات المهندس: الأجهزة، العيادات، وأنواع الأجهزة.
class EngineerRepository {
  EngineerRepository(this._client);
  final ApiClient _client;

  List<T> _extractList<T>(dynamic data, T Function(Map<String, dynamic>) fromJson) {
    final results = data is Map && data.containsKey('results') ? data['results'] as List : data as List;
    return results.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Devices ---

  Future<List<EngineerDeviceModel>> fetchDevices() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.devices);
      return _extractList(response.data, EngineerDeviceModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<EngineerDeviceModel> createDevice(NewDevicePayload payload) async {
    try {
      final response = await _client.raw.post(ApiEndpoints.devices, data: payload.toJson());
      return EngineerDeviceModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// كل الحالات (عبر الزمن) التي ارتبطت بجهاز معيّن — لشاشة تفاصيل الجهاز
  Future<List<CaseSummaryModel>> fetchCasesForDevice(String deviceId) async {
    try {
      final response = await _client.raw.get(
        ApiEndpoints.cases,
        queryParameters: {'device': deviceId},
      );
      return _extractList(response.data, CaseSummaryModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// عدد الجلسات المسجّلة لحالة معيّنة — لعرض "حالة الالتزام" ببساطة
  Future<int> fetchSessionsCountForCase(int caseId) async {
    try {
      final response = await _client.raw.get(
        ApiEndpoints.sessions,
        queryParameters: {'case': caseId},
      );
      final data = response.data;
      final results = data is Map && data.containsKey('results') ? data['results'] as List : data as List;
      return results.length;
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  // --- Clinics ---

  Future<List<ClinicModel>> fetchClinics() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.clinics);
      return _extractList(response.data, ClinicModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<ClinicModel> createClinic(ClinicPayload payload) async {
    try {
      final response = await _client.raw.post(ApiEndpoints.clinics, data: payload.toJson());
      return ClinicModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// فريق المهندسين — لاختيار "المهندس المسؤول" عند إنشاء عيادة
  Future<List<EngineerModel>> fetchEngineers() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.engineers);
      return _extractList(response.data, EngineerModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// قائمة الأطباء كاملة، حتى إن لم ترتبط بهم حالات حتى الآن.
  Future<List<DoctorModel>> fetchDoctors() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.doctors);
      return _extractList(response.data, DoctorModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<List<PatientModel>> fetchPatients() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.patients);
      return _extractList(response.data, PatientModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// المهندس يملك صلاحية قراءة كل الحالات؛ يحتوي الرد على الجلسات المنجزة.
  Future<List<CaseModel>> fetchAllCases() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.cases);
      return _extractList(response.data, CaseModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  // --- Device Types ---

  Future<List<DeviceTypeModel>> fetchDeviceTypes() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.deviceTypes);
      return _extractList(response.data, DeviceTypeModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<DeviceTypeModel> createDeviceType(DeviceTypePayload payload) async {
    try {
      final response = await _client.raw.post(ApiEndpoints.deviceTypes, data: payload.toJson());
      return DeviceTypeModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
