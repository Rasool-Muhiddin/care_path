import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (_) {
      if (!silent) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    final sent = await _repo.sendMessage(
      conversation.caseId,
      conversation.inquiryType,
      text.trim(),
    );
    state = state.copyWith(messages: [...state.messages, sent]);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, ChatConversation>(
  (ref, conversation) => ChatNotifier(ref.watch(chatRepositoryProvider), conversation),
);

final unreadCountProvider = StreamProvider<int>((ref) async* {
  final repo = ref.watch(chatRepositoryProvider);
  while (true) {
    try {
      yield await repo.getUnreadTotal();
    } catch (_) {
      yield 0;
    }
    await Future.delayed(const Duration(seconds: 15));
  }
});

/// خريطة {caseId: عدد غير المقروء} — تُستخدم لعرض badge بجانب كل Case بالواجهة
final unreadByCaseProvider = StreamProvider<Map<int, int>>((ref) async* {
  final repo = ref.watch(chatRepositoryProvider);
  while (true) {
    try {
      yield await repo.getUnreadByCase();
    } catch (_) {
      yield {};
    }
    await Future.delayed(const Duration(seconds: 15));
  }
});
