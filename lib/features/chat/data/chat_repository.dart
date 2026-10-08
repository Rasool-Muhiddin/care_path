import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/auth/auth_state.dart'; // فيه تعريف apiClientProvider
import 'chat_message_model.dart';

class ChatRepository {
  final ApiClient _apiClient;
  ChatRepository(this._apiClient);

  /// حجم صفحة تاريخ المحادثة في الخادم (chat.views.CHAT_PAGE_SIZE)
  static const pageSize = 50;

  /// بلا معاملات: آخر [pageSize] رسالة (أول فتح للشاشة).
  /// [afterId]: كل الرسائل الأحدث من هذا الـ id (polling تزايدي).
  /// [beforeId]: الـ [pageSize] رسالة الأقدم منه (التمرير للأعلى).
  /// الرد دائماً من الأقدم للأحدث.
  Future<List<ChatMessageModel>> getMessages(
    int caseId,
    InquiryType inquiryType, {
    int? afterId,
    int? beforeId,
  }) async {
    try {
      final response = await _apiClient.raw.get(
        ApiEndpoints.caseMessages(caseId),
        queryParameters: {
          'inquiry_type': inquiryType.apiValue,
          if (afterId != null) 'after_id': afterId,
          if (beforeId != null) 'before_id': beforeId,
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
