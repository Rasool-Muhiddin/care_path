import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/notifications/fcm_service.dart';
import '../../doctor/models/case_model.dart';
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

  /// هل في الخادم رسائل أقدم من أول رسالة محمّلة؟
  final bool hasOlder;
  final bool isLoadingOlder;

  /// حالة الحالة كما أرسلها الخادم مع آخر تحميل؛ null قبل أول رد.
  final CaseStatus? caseStatus;

  ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.caseStatus,
  });

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    bool? isLoading,
    bool? hasOlder,
    bool? isLoadingOlder,
    CaseStatus? caseStatus,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        hasOlder: hasOlder ?? this.hasOlder,
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        caseStatus: caseStatus ?? this.caseStatus,
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repo;
  final ChatConversation conversation;
  Timer? _pollTimer;
  StreamSubscription<int>? _incomingSubscription;

  /// أحدث id جاء من الخادم عبر الـ polling. لا يتأثر برسائل أرسلناها نحن،
  /// حتى لا نتخطى رسالة من الطرف الآخر حُفظت قبل رسالتنا مباشرة.
  int? _lastPolledId;
  bool _isLoading = false;
  bool _reloadQueued = false;

  static const _pollInterval = Duration(seconds: 8);

  ChatNotifier(this._repo, this.conversation, Stream<int> incomingChatMessages)
      : super(ChatState()) {
    _load();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
    // رسالة FCM لهذه الحالة والتطبيق مفتوح: نحدّث فوراً بدل انتظار المؤقّت
    _incomingSubscription = incomingChatMessages
        .where((caseId) => caseId == conversation.caseId)
        .listen((_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (_isLoading) {
      // طلب جارٍ بدأ قبل وصول الرسالة الجديدة ربما — نعيد مرة بعد انتهائه
      _reloadQueued = true;
      return;
    }
    _isLoading = true;
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final isFirstPage = _lastPolledId == null;
      final page = await _repo.getMessages(
        conversation.caseId,
        conversation.inquiryType,
        afterId: _lastPolledId,
      );
      // الشاشة قد تُغلق أثناء الطلب (autoDispose) — لا نكتب حالة بعد التفكيك
      if (!mounted) return;
      final fetched = page.messages;
      for (final message in fetched) {
        if (_lastPolledId == null || message.id > _lastPolledId!) _lastPolledId = message.id;
      }
      state = state.copyWith(
        messages: _merge(state.messages, fetched),
        isLoading: false,
        // أول تحميل يرجع آخر صفحة فقط؛ صفحة ممتلئة تعني غالباً وجود أقدم منها
        hasOlder: isFirstPage ? fetched.length >= ChatRepository.pageSize : null,
        // أُغلقت الحالة أثناء فتح المحادثة: الشاشة تخفي حقل الكتابة في هذا التحديث
        caseStatus: page.caseStatus,
      );
    } catch (_) {
      if (!silent && mounted) state = state.copyWith(isLoading: false);
    } finally {
      _isLoading = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        _load(silent: true);
      }
    }
  }

  /// يضيف الجديد فقط (بلا تكرار لرسالة أرسلناها وجاءت أيضاً من الـ polling)
  /// ويرتّب حسب الـ id، أي حسب ترتيب الحفظ في الخادم.
  static List<ChatMessageModel> _merge(
    List<ChatMessageModel> existing,
    List<ChatMessageModel> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final knownIds = existing.map((m) => m.id).toSet();
    return [...existing, ...incoming.where((m) => !knownIds.contains(m.id))]
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  /// يحمّل الصفحة الأقدم من أول رسالة معروضة (عند التمرير لأعلى المحادثة).
  Future<void> loadOlder() async {
    if (!state.hasOlder || state.isLoadingOlder || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingOlder: true);
    try {
      final page = await _repo.getMessages(
        conversation.caseId,
        conversation.inquiryType,
        beforeId: state.messages.first.id,
      );
      if (!mounted) return;
      state = state.copyWith(
        messages: _merge(state.messages, page.messages),
        hasOlder: page.messages.length >= ChatRepository.pageSize,
        isLoadingOlder: false,
        caseStatus: page.caseStatus,
      );
    } catch (_) {
      // فشل مؤقت: يمكن المحاولة مجدداً بالتمرير للأعلى مرة أخرى
      if (mounted) state = state.copyWith(isLoadingOlder: false);
    }
  }

  /// تحديث فوري خارج دورة الـ polling (مثلاً بعد رفض الإرسال بـ 403 لأن
  /// الحالة أُغلقت).
  void refresh() => _load(silent: true);

  /// يرمي الاستثناء عند الفشل كي تُبقي الشاشة النص وتعرض الخطأ.
  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    final sent = await _repo.sendMessage(
      conversation.caseId,
      conversation.inquiryType,
      text.trim(),
    );
    if (!mounted) return;
    state = state.copyWith(messages: _merge(state.messages, [sent]));
  }

  /// مثل [send]: يرمي الاستثناء عند الفشل كي تُبقي الشاشة التسجيل للمحاولة مجدداً.
  Future<void> sendVoice(String filePath) async {
    final sent = await _repo.sendVoice(conversation.caseId, conversation.inquiryType, filePath);
    if (!mounted) return;
    state = state.copyWith(messages: _merge(state.messages, [sent]));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _incomingSubscription?.cancel();
    super.dispose();
  }
}

/// autoDispose: يتوقف مؤقّت الـ polling (عبر ChatNotifier.dispose) فور
/// مغادرة شاشة المحادثة، ولا تُعلَّم الرسائل كمقروءة في الخلفية.
final chatProvider =
    StateNotifierProvider.autoDispose.family<ChatNotifier, ChatState, ChatConversation>(
  (ref, conversation) => ChatNotifier(
    ref.watch(chatRepositoryProvider),
    conversation,
    FcmService.instance.chatMessages,
  ),
);

/// خريطة {caseId: عدد غير المقروء} — تُستخدم لعرض badge بجانب كل Case بالواجهة.
/// الـ polling الوحيد لعدّاد غير المقروء: كل 15 ثانية، أو فوراً عند وصول
/// رسالة FCM. يتوقف حين لا يستمع أحد (autoDispose)، وفور تسجيل الخروج:
/// مشاهدة authStateProvider تعيد بناء الـ provider فيُفكَّك الـ stream القديم.
final unreadByCaseProvider = StreamProvider.autoDispose<Map<int, int>>((ref) async* {
  if (ref.watch(authStateProvider) is! AuthAuthenticated) return;
  final repo = ref.watch(chatRepositoryProvider);

  var active = true;
  Completer<void>? wake;
  final incoming = FcmService.instance.chatMessages.listen((_) {
    final pending = wake;
    if (pending != null && !pending.isCompleted) pending.complete();
  });
  ref.onDispose(() {
    active = false;
    incoming.cancel();
  });

  while (active) {
    try {
      yield await repo.getUnreadByCase();
    } catch (_) {
      yield const <int, int>{};
    }
    final next = Completer<void>();
    wake = next;
    await Future.any([Future<void>.delayed(const Duration(seconds: 15)), next.future]);
  }
});
