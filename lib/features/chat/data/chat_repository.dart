import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/auth/auth_state.dart'; // فيه تعريف apiClientProvider
import 'chat_message_model.dart';

class ChatRepository {
  final ApiClient _apiClient;
  ChatRepository(this._apiClient);

  /// [afterId]: يرجع فقط الرسائل الأحدث من هذا الـ id (polling تزايدي)؛
  /// بدونه يرجع المحادثة كاملة (أول تحميل للشاشة).
  Future<List<ChatMessageModel>> getMessages(
    int caseId,
    InquiryType inquiryType, {
    int? afterId,
  }) async {
    try {
      final response = await _apiClient.raw.get(
        ApiEndpoints.caseMessages(caseId),
        queryParameters: {
          'inquiry_type': inquiryType.apiValue,
          if (afterId != null) 'after_id': afterId,
        },
      );
      return (response.data as List).map((e) => ChatMessageModel.fromJson(e)).toList();
    } on DioException catch (e) {
      throw _apiClient.mapError(e);
    }
  }

  Future<ChatMessageModel> sendMessage(int caseId, InquiryType inquiryType, String text) async {
    try {
      final response = await _apiClient.raw.post(
        ApiEndpoints.caseMessages(caseId),
        data: {'text': text, 'inquiry_type': inquiryType.apiValue},
      );
      return ChatMessageModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _apiClient.mapError(e);
    }
  }

  /// عدد الرسائل غير المقروءة لكل Case على حدة — لعرض badge بجانب كل حالة
  Future<Map<int, int>> getUnreadByCase() async {
    try {
      final response = await _apiClient.raw.get(ApiEndpoints.chatUnreadCount);
      final byCase = response.data['by_case'] as Map<String, dynamic>? ?? {};
      return byCase.map((key, value) => MapEntry(int.parse(key), value as int));
    } on DioException catch (e) {
      throw _apiClient.mapError(e);
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(apiClientProvider));
});
