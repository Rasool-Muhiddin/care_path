import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../doctor/models/case_model.dart' show CaseModel;
import '../models/session_model.dart';

/// طبقة التواصل مع بيانات المريض: حالته الخاصة، جلساته، وتسجيل جلسة جديدة.
class PatientRepository {
  PatientRepository(this._client);
  final ApiClient _client;

  /// يجلب جلسات المريض الحالي.
  /// الـ backend يفلتر تلقائياً حسب هوية المستخدم المسجّل دخوله
  /// (نفس منطق queryset في CaseViewSet)، لذا لا حاجة لإرسال أي معرف هنا.
  Future<List<SessionModel>> fetchMySessions() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.sessions);
      return items.map(SessionModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// يجلب حالة (Case) المريض الحالي — الـ backend يفلتر تلقائياً فيرجّع
  /// فقط حالاته الخاصة. نفترض حالة نشطة واحدة؛ لو عنده أكثر من حالة،
  /// نُفضّل أحدث حالة غير مغلقة.
  Future<CaseModel?> fetchMyCase() async {
    try {
      final items = await _client.getAllPages(ApiEndpoints.cases);
      final cases = items.map(CaseModel.fromJson).toList();
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