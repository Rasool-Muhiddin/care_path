import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/notifications/fcm_service.dart';
import '../data/chat_repository.dart';
import '../data/engineer_conversation_model.dart';

class EngineerInboxState {
  final List<EngineerConversationModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  const EngineerInboxState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  EngineerInboxState copyWith({
    List<EngineerConversationModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      EngineerInboxState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : error ?? this.error,
      );
}

/// صندوق رسائل المهندس لفلتر واحد ([mine] = "عياداتي" أو "الكل").
/// صفحات بالتمرير ([loadMore])، ويُعاد التحميل من الأول عند السحب، عند
/// وصول رسالة FCM، أو عند الرجوع من شاشة المحادثة.
class EngineerInboxNotifier extends StateNotifier<EngineerInboxState> {
  EngineerInboxNotifier(this._repo, this.mine, Stream<int> incomingChatMessages)
      : super(const EngineerInboxState(isLoading: true)) {
    refresh();
    _incomingSubscription = incomingChatMessages.listen((_) => refresh());
  }

  final ChatRepository _repo;
  final bool mine;
  StreamSubscription<int>? _incomingSubscription;
  int _loadedPages = 0;
  // يُهمل رد تحديث أقدم وصل بعد تحديث أحدث
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    if (state.items.isEmpty) state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _repo.getEngineerInbox(page: 1, mine: mine);
      if (!mounted || generation != _generation) return;
      _loadedPages = 1;
      state = EngineerInboxState(items: page.items, hasMore: page.hasNext);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      // فشل تحديث صامت مع وجود بيانات: نُبقيها بدل استبدالها بشاشة خطأ
      state = state.items.isEmpty
          ? EngineerInboxState(error: e)
          : state.copyWith(isLoading: false);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.getEngineerInbox(page: _loadedPages + 1, mine: mine);
      if (!mounted || generation != _generation) return;
      _loadedPages++;
      // رسالة جديدة بين الطلبين قد تُزيح محادثة للصفحة التالية فتتكرر
      final known = state.items.map((c) => c.caseId).toSet();
      state = state.copyWith(
        items: [...state.items, ...page.items.where((c) => !known.contains(c.caseId))],
        hasMore: page.hasNext,
        isLoadingMore: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoadingMore: false);
    }
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    super.dispose();
  }
}

final engineerInboxProvider =
    StateNotifierProvider.autoDispose.family<EngineerInboxNotifier, EngineerInboxState, bool>(
  (ref, mine) {
    // تسجيل خروج/دخول بحساب آخر يعيد بناء الصندوق من الصفر
    ref.watch(authStateProvider);
    return EngineerInboxNotifier(
      ref.watch(chatRepositoryProvider),
      mine,
      FcmService.instance.chatMessages,
    );
  },
);

/// حق المهندس في الرد بالقناة التقنية لحالة — لشاشة المحادثة.
final replyRightsProvider = FutureProvider.autoDispose.family<ReplyRights, int>((ref, caseId) {
  return ref.watch(chatRepositoryProvider).getReplyRights(caseId);
});
