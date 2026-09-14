import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/chat_message_model.dart';
import '../data/chat_repository.dart';

class ChatState {
  final List<ChatMessageModel> messages;
  final bool isLoading;
  ChatState({this.messages = const [], this.isLoading = false});
  ChatState copyWith({List<ChatMessageModel>? messages, bool? isLoading}) =>
      ChatState(messages: messages ?? this.messages, isLoading: isLoading ?? this.isLoading);
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repo;
  final int caseId;
  Timer? _pollTimer;

  ChatNotifier(this._repo, this.caseId) : super(ChatState()) {
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final messages = await _repo.getMessages(caseId);
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (_) {
      if (!silent) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    final sent = await _repo.sendMessage(caseId, text.trim());
    state = state.copyWith(messages: [...state.messages, sent]);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, int>(
  (ref, caseId) => ChatNotifier(ref.watch(chatRepositoryProvider), caseId),
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