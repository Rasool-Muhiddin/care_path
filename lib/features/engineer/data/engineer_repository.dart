import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../doctor/models/case_model.dart';
import '../../patient/models/session_model.dart';
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

  // --- Devices ---

  Future<List<EngineerDeviceModel>> fetchDevices() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.devices);
      return items.map(EngineerDeviceModel.fromJson).toList();
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

  /// تعديل جهاز موجود (رقم الجهاز id هو UUID كسلسلة نصية).
  Future<EngineerDeviceModel> updateDevice(String id, NewDevicePayload payload) async {
    try {
      final response =
          await _client.raw.patch('${ApiEndpoints.devices}$id/', data: payload.toJson());
      return EngineerDeviceModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// كل الحالات (عبر الزمن) التي ارتبطت بجهاز معيّن — لشاشة تفاصيل الجهاز
  Future<List<CaseSummaryModel>> fetchCasesForDevice(String deviceId) async {
    try {
      final items = await _client.getAllPages(
        ApiEndpoints.cases,
        queryParameters: {'device': deviceId},
      );
      return items.map(CaseSummaryModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }


  /// كل جلسات حالة معيّنة (مع التواريخ) — لشاشة تفاصيل المريض عند المهندس
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

  // --- Clinics ---

  Future<List<ClinicModel>> fetchClinics() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.clinics);
      return items.map(ClinicModel.fromJson).toList();
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

  /// تعديل عيادة موجودة.
  Future<ClinicModel> updateClinic(int id, ClinicPayload payload) async {
    try {
      final response =
          await _client.raw.patch('${ApiEndpoints.clinics}$id/', data: payload.toJson());
      return ClinicModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// فريق المهندسين — لاختيار "المهندس المسؤول" عند إنشاء عيادة
  Future<List<EngineerModel>> fetchEngineers() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.engineers);
      return items.map(EngineerModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// قائمة الأطباء كاملة، حتى إن لم ترتبط بهم حالات حتى الآن.
  Future<List<DoctorModel>> fetchDoctors() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.doctors);
      return items.map(DoctorModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<List<PatientModel>> fetchPatients() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.patients);
      return items.map(PatientModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// المهندس يملك صلاحية قراءة كل الحالات؛ يحتوي الرد على الجلسات المنجزة.
  Future<List<CaseModel>> fetchAllCases() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.cases);
      return items.map(CaseModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  // --- Device Types ---

  Future<List<DeviceTypeModel>> fetchDeviceTypes() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.deviceTypes);
      return items.map(DeviceTypeModel.fromJson).toList();
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

  /// تعديل نوع جهاز موجود.
  Future<DeviceTypeModel> updateDeviceType(int id, DeviceTypePayload payload) async {
    try {
      final response =
          await _client.raw.patch('${ApiEndpoints.deviceTypes}$id/', data: payload.toJson());
      return DeviceTypeModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}