import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../doctor/models/case_model.dart' show CaseModel;
import '../models/session_model.dart';

/// طبقة التواصل مع بيانات المريض: حالته الخاصة، جلساته، وتسجيل جلسة جديدة.
class PatientRepository {
  PatientRepository(this._client);
  final ApiClient _client;

  List<T> _extractList<T>(dynamic data, T Function(Map<String, dynamic>) fromJson) {
    final results = data is Map && data.containsKey('results') ? data['results'] as List : data as List;
    return results.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  /// يجلب جلسات المريض الحالي.
  /// الـ backend يفلتر تلقائياً حسب هوية المستخدم المسجّل دخوله
  /// (نفس منطق queryset في CaseViewSet)، لذا لا حاجة لإرسال أي معرف هنا.
  Future<List<SessionModel>> fetchMySessions() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.sessions);
      return _extractList(response.data, SessionModel.fromJson);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// يجلب حالة (Case) المريض الحالي — الـ backend يفلتر تلقائياً فيرجّع
  /// فقط حالاته الخاصة. نفترض حالة نشطة واحدة؛ لو عنده أكثر من حالة،
  /// نُفضّل أحدث حالة غير مغلقة.
  Future<CaseModel?> fetchMyCase() async {
    try {
      final response = await _client.raw.get(ApiEndpoints.cases);
      final cases = _extractList(response.data, CaseModel.fromJson);
      if (cases.isEmpty) return null;
      final active = cases.where((c) => c.status.apiValue != 'closed');
      return active.isNotEmpty ? active.first : cases.first;
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// تسجيل جلسة جديدة ("تم إنهاء الجلسة") من طرف المريض نفسه
  Future<SessionModel> createSession(NewSessionPayload payload) async {
    try {
      final response = await _client.raw.post(ApiEndpoints.sessions, data: payload.toJson());
      return SessionModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}