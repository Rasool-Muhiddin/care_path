import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_state.dart';
import '../data/chat_message_model.dart';
import '../data/chat_repository.dart';

class ChatConversation {
  const ChatConversation(this.caseId, this.inquiryType);

  final int caseId;
  final InquiryType inquiryType;

  @override
  bool operator ==(Object other) =>
      other is ChatConversation &&
      other.caseId == caseId &&
      other.inquiryType == inquiryType;

  @override
  int get hashCode => Object.hash(caseId, inquiryType);
}

class ChatState {
  final List<ChatMessageModel> messages;
  final bool isLoading;
  ChatState({this.messages = const [], this.isLoading = false});
  ChatState copyWith({List<ChatMessageModel>? messages, bool? isLoading}) =>
      ChatState(messages: messages ?? this.messages, isLoading: isLoading ?? this.isLoading);
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repo;
  final ChatConversation conversation;
  Timer? _pollTimer;

  ChatNotifier(this._repo, this.conversation) : super(ChatState()) {
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final messages = await _repo.getMessages(
        conversation.caseId,
        conversation.inquiryType,
      );
      // الشاشة قد تُغلق أثناء الطلب (autoDispose) — لا نكتب حالة بعد التفكيك
      if (!mounted) return;
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (_) {
      if (!silent && mounted) state = state.copyWith(isLoading: false);
    }
  }

  /// يرمي الاستثناء عند الفشل كي تُبقي الشاشة النص وتعرض الخطأ.
  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    final sent = await _repo.sendMessage(
      conversation.caseId,
      conversation.inquiryType,
      text.trim(),
    );
    if (!mounted) return;
    state = state.copyWith(messages: [...state.messages, sent]);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// autoDispose: يتوقف مؤقّت الـ polling (عبر ChatNotifier.dispose) فور
/// مغادرة شاشة المحادثة، ولا تُعلَّم الرسائل كمقروءة في الخلفية.
final chatProvider =
    StateNotifierProvider.autoDispose.family<ChatNotifier, ChatState, ChatConversation>(
  (ref, conversation) => ChatNotifier(ref.watch(chatRepositoryProvider), conversation),
);

/// يكرر [fetch] كل 15 ثانية ما دام المستخدم مسجّل دخوله وهناك من يستمع.
/// مشاهدة authStateProvider تعيد بناء الـ provider عند الخروج، فيُفكَّك
/// الـ stream القديم وتتوقف الحلقة حتى لو بقيت شاشة تستمع لحظة الانتقال.
Stream<T> _pollWhileLoggedIn<T>(
  Ref ref,
  Future<T> Function() fetch,
  T fallback,
) async* {
  if (ref.watch(authStateProvider) is! AuthAuthenticated) return;
  var active = true;
  ref.onDispose(() => active = false);
  while (active) {
    try {
      yield await fetch();
    } catch (_) {
      yield fallback;
    }
    await Future.delayed(const Duration(seconds: 15));
  }
}

final unreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return _pollWhileLoggedIn(ref, repo.getUnreadTotal, 0);
});

/// خريطة {caseId: عدد غير المقروء} — تُستخدم لعرض badge بجانب كل Case بالواجهة
final unreadByCaseProvider = StreamProvider.autoDispose<Map<int, int>>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return _pollWhileLoggedIn(ref, repo.getUnreadByCase, const <int, int>{});
});
