import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'attack_models.dart';

/// النوبات وتأكيداتها — endpoint واحد لكل الأدوار (الـ backend يفلتر حسب
/// الدور عبر scope_by_case)، فطبقة واحدة مشتركة بدل نسخة لكل دور.
class AttackRepository {
  AttackRepository(this._client);
  final ApiClient _client;

  Future<List<AttackEventModel>> fetchAttacks(int caseId) async {
    try {
      final items = await _client.getAllPages(
        ApiEndpoints.attackEvents,
        queryParameters: {'case': caseId},
      );
      return items.map(AttackEventModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<AttackEventModel> logAttack(NewAttackEventPayload payload) async {
    try {
      final response = await _client.raw.post(ApiEndpoints.attackEvents, data: payload.toJson());
      return AttackEventModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<void> deleteAttack(int attackId) async {
    try {
      await _client.raw.delete('${ApiEndpoints.attackEvents}$attackId/');
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<List<AttackLogConfirmationModel>> fetchConfirmations(int caseId) async {
    try {
      final items = await _client.getAllPages(
        ApiEndpoints.attackLogConfirmations,
        queryParameters: {'case': caseId},
      );
      return items.map(AttackLogConfirmationModel.fromJson).toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<void> confirmLog({required int caseId, required bool hadUnlogged}) async {
    try {
      await _client.raw.post(
        ApiEndpoints.attackLogConfirmations,
        data: {'case': caseId, 'had_unlogged': hadUnlogged},
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}

final attackRepositoryProvider = Provider<AttackRepository>((ref) {
  return AttackRepository(ref.read(apiClientProvider));
});

/// كل نوبات حالة معيّنة (كل الصفحات) — للمريض والطبيب والمهندس.
final caseAttacksProvider =
    FutureProvider.autoDispose.family<List<AttackEventModel>, int>((ref, caseId) async {
  return ref.read(attackRepositoryProvider).fetchAttacks(caseId);
});

/// كل تأكيدات "لا نوبات غير مسجّلة" لحالة معيّنة.
final caseAttackConfirmationsProvider =
    FutureProvider.autoDispose.family<List<AttackLogConfirmationModel>, int>((ref, caseId) async {
  return ref.read(attackRepositoryProvider).fetchConfirmations(caseId);
});
