import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/auth/auth_state.dart'; // فيه تعريف apiClientProvider
import '../../doctor/models/case_model.dart';
import 'chat_message_model.dart';
import 'engineer_conversation_model.dart';
import 'voice_platform.dart';

/// صفحة رسائل من الخادم. [caseStatus] null إن لم يرسل الخادم الـ header.
class ChatPage {
  const ChatPage(this.messages, this.caseStatus);
  final List<ChatMessageModel> messages;
  final CaseStatus? caseStatus;
}

class ChatRepository {
  final ApiClient _apiClient;
  ChatRepository(this._apiClient);

  /// حجم صفحة تاريخ المحادثة في الخادم (chat.views.CHAT_PAGE_SIZE)
  static const pageSize = 50;

  /// بلا معاملات: آخر [pageSize] رسالة (أول فتح للشاشة).
  /// [afterId]: كل الرسائل الأحدث من هذا الـ id (polling تزايدي).
  /// [beforeId]: الـ [pageSize] رسالة الأقدم منه (التمرير للأعلى).
  /// الرد دائماً من الأقدم للأحدث، ومعه حالة الحالة (header X-Case-Status)
  /// كي تخفي الشاشة حقل الكتابة فور إغلاق الحالة.
  Future<ChatPage> getMessages(
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
      final status = response.headers.value('x-case-status');
      return ChatPage(
        (response.data as List).map((e) => ChatMessageModel.fromJson(e)).toList(),
        status == null ? null : CaseStatus.fromApiValue(status),
      );
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

  /// رسالة صوتية: multipart على نفس endpoint النص، فتمر بنفس قواعد الإرسال
  /// في الخادم. [recording]: مسار ملف m4a (أندرويد/iOS) أو blob URL (ويب).
  /// الخادم يحوّل كل تسجيل إلى AAC m4a ويقرأ المدة من الملف نفسه.
  Future<ChatMessageModel> sendVoice(int caseId, InquiryType inquiryType, String recording) async {
    try {
      final response = await _apiClient.raw.post(
        ApiEndpoints.caseMessages(caseId),
        data: FormData.fromMap({
          'inquiry_type': inquiryType.apiValue,
          'audio': await voiceUploadFile(recording),
        }),
        // رفع حتى دقيقتين من الصوت على شبكة ضعيفة
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
      return ChatMessageModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _apiClient.mapError(e);
    }
  }

  /// يحمّل ملف الرسالة الصوتية بتوكن الدخول (عبر الـ interceptor، ومنه
  /// تجديد التوكن عند 401). الحفظ في VoiceCache حسب المنصة.
  Future<List<int>> downloadVoice(String audioUrl) async {
    try {
      final response = await _apiClient.raw.get<List<int>>(
        '${ApiEndpoints.baseUrl}$audioUrl',
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
      );
      return response.data!;
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

  /// حجم صفحة صندوق رسائل المهندس
  static const inboxPageSize = 30;

  /// صفحة من صندوق رسائل المهندس، الأحدث رسالةً أولاً.
  /// [mine]: المحادثات التي يستطيع المهندس الرد فيها فقط (عياداته أو بلا مسؤول).
  Future<InboxPage> getEngineerInbox({required int page, required bool mine}) async {
    try {
      final response = await _apiClient.raw.get(
        ApiEndpoints.engineerInbox,
        queryParameters: {
          'page': page,
          'page_size': inboxPageSize,
          if (mine) 'mine': 'true',
        },
      );
      final data = response.data as Map<String, dynamic>;
      final items = (data['results'] as List)
          .map((e) => EngineerConversationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return InboxPage(items, data['next'] != null);
    } on DioException catch (e) {
      throw _apiClient.mapError(e);
    }
  }

  Future<ReplyRights> getReplyRights(int caseId) async {
    try {
      final response = await _apiClient.raw.get(ApiEndpoints.caseReplyRights(caseId));
      return ReplyRights.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _apiClient.mapError(e);
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(apiClientProvider));
});
