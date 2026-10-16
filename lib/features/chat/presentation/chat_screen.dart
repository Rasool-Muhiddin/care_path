import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart'; // عدّل المسار إذا كان مختلفًا
import '../../../core/auth/auth_state.dart';
import '../../../core/network/api_client.dart';
import '../../../core/permissions/user_role.dart';
import '../data/chat_message_model.dart';
import '../data/engineer_conversation_model.dart';
import '../logic/chat_notifier.dart';
import '../logic/engineer_inbox_notifier.dart';

/// Chat-only background: a deep teal-to-navy gradient with a soft glow
/// near the top, distinct from [AppGradientBackground] so the messaging
/// screen reads differently from the rest of the app at a glance.
/// Deliberately local to this file — it doesn't touch or replace the
/// shared background widget used everywhere else.
class _ChatGradientBackground extends StatelessWidget {
  const _ChatGradientBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1638), // AppGlassColors.baseDark
            Color(0xFF0F2E45), // teal-tinted navy — the "messaging" note
            Color(0xFF102A4A),
            Color(0xFF0A1638),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.6, -0.9),
            radius: 1.3,
            colors: [
              const Color(0xFF22D3EE).withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const banner = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600);
  static const senderName = TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold);
  static const bubbleTextMine = TextStyle(color: Colors.white, fontSize: 14);
  static const bubbleTextTheirs = TextStyle(color: Colors.white, fontSize: 14);
  static const readOnly = TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500);
  static const pickerTitle = TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold);
  static const pickerBody = TextStyle(color: Colors.white70, fontSize: 13);
  static const optionTitle = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold);
  static const optionSubtitle = TextStyle(color: Colors.white70, fontSize: 12);
}

class ChatScreen extends ConsumerStatefulWidget {
  final int caseId;

  /// اسم الطبيب المعالج (اختياري) — يُعرض للمريض في سطر "إلى: ..." بالقناة الطبية.
  final String? doctorName;

  /// للمهندس: حق الرد المعروف مسبقاً (من صندوق الرسائل) يُعرض فوراً إلى
  /// أن يصل رد الخادم (replyRightsProvider).
  final ReplyRights? initialReplyRights;
  const ChatScreen({super.key, required this.caseId, this.doctorName, this.initialReplyRights});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  InquiryType? _selectedInquiryType;
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final currentRole = authState is AuthAuthenticated ? authState.user.role : null;
    final isStaff = currentRole == UserRole.doctor || currentRole == UserRole.engineer;

    // لا ندخل أي قناة قبل أن يحدد المريض نوع سؤاله. هذا يمنع إرسال
    // استفسار تقني للطبيب بالخطأ، ويجعل القناتين واضحتين منذ البداية.
    if (currentRole == UserRole.patient && _selectedInquiryType == null) {
      return _InquiryTypePicker(
        onSelect: (type) => setState(() => _selectedInquiryType = type),
      );
    }

    final inquiryType =
        currentRole == UserRole.doctor ? InquiryType.medical : _selectedInquiryType ?? InquiryType.technical;
    // المهندس يرى القناة الطبية كمدير لكن للقراءة فقط.
    final isEngineerMedicalReadOnly = currentRole == UserRole.engineer && inquiryType == InquiryType.medical;
    // وفي القناة التقنية يرد المهندس المسؤول عن عيادة الجهاز فقط (والخادم
    // يرفض غيره بـ 403). أثناء التحميل/عند الفشل يبقى الحقل ظاهراً.
    final replyRights = currentRole == UserRole.engineer && inquiryType == InquiryType.technical
        ? ref.watch(replyRightsProvider(widget.caseId)).valueOrNull ?? widget.initialReplyRights
        : null;
    final isEngineerTechnicalReadOnly = replyRights != null && !replyRights.canReply;
    final doctorLabel = (widget.doctorName != null && widget.doctorName!.trim().isNotEmpty)
        ? 'د. ${widget.doctorName!.trim()}'
        : 'الطبيب المعالج';
    final recipientLabel = currentRole == UserRole.patient
        ? (inquiryType == InquiryType.technical ? 'إلى: المهندس' : 'إلى: $doctorLabel')
        : null;
    final conversation = ChatConversation(widget.caseId, inquiryType);
    final state = ref.watch(chatProvider(conversation));

    final content = Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(inquiryType.arabicLabel, style: const TextStyle(color: Colors.white)),
        leading: currentRole == UserRole.patient
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'تغيير نوع الاستفسار',
                onPressed: () => setState(() => _selectedInquiryType = null),
              )
            : null,
        // اختيار القناة للمدير فقط: المهندس العادي لا يرى القناة الطبية
        // (مريض ↔ طبيب)، فتبقى له القناة التقنية وحدها.
        actions: currentRole == UserRole.engineer && ref.watch(isManagerProvider)
            ? [
                PopupMenuButton<InquiryType>(
                  tooltip: 'اختيار قناة المحادثة',
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: AppGlassColors.baseDark,
                  onSelected: (type) => setState(() => _selectedInquiryType = type),
                  itemBuilder: (context) => InquiryType.values
                      .map(
                        (type) => PopupMenuItem(
                          value: type,
                          child: Text(
                            type.arabicLabel,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ]
            : null,
      ),
      body: _ChatGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (recipientLabel != null) _RecipientBanner(label: recipientLabel),
              Expanded(
                child: state.isLoading && state.messages.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : NotificationListener<ScrollUpdateNotification>(
                        // التمرير لأعلى حتى بداية القائمة يحمّل الرسائل الأقدم
                        onNotification: (notification) {
                          final delta = notification.scrollDelta ?? 0;
                          if (delta < 0 && notification.metrics.pixels <= 80) {
                            ref.read(chatProvider(conversation).notifier).loadOlder();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          // صف إضافي في الأعلى ما دام في الخادم رسائل أقدم
                          itemCount: state.messages.length + (state.hasOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (state.hasOlder && index == 0) {
                              return _LoadOlderRow(
                                isLoading: state.isLoadingOlder,
                                label: isStaff ? 'Load earlier messages' : 'عرض الرسائل الأقدم',
                                onPressed: () => ref.read(chatProvider(conversation).notifier).loadOlder(),
                              );
                            }
                            final msg = state.messages[index - (state.hasOlder ? 1 : 0)];
                            return Align(
                              alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: GlassContainer(
                                    borderRadius: 14,
                                    opacity: msg.isMine ? 0.22 : 0.10,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!msg.isMine) Text(msg.senderName, style: _Txt.senderName),
                                        Text(
                                          msg.text,
                                          style: msg.isMine ? _Txt.bubbleTextMine : _Txt.bubbleTextTheirs,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (isEngineerMedicalReadOnly)
                const _ReadOnlyBar(
                  text: 'View only — medical conversation between the patient and the doctor.',
                )
              else if (isEngineerTechnicalReadOnly)
                _ReadOnlyBar(
                  text: 'Read only — responsible: Eng. ${replyRights.responsibleEngineerName ?? '—'}',
                )
              else
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GlassContainer(
                    borderRadius: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            style: const TextStyle(color: Colors.white),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: isStaff ? 'Type a message...' : 'اكتب رسالة...',
                              hintStyle: const TextStyle(color: Colors.white54),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _isSending ? null : _send,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // تبقى واجهة المريض RTL؛ حسابات الكادر تستخدم الغلاف الموجود سابقاً.
    return isStaff ? LtrScope(child: content) : content;
  }

  /// يُمسح الحقل فقط بعد نجاح الإرسال؛ عند الفشل يبقى النص كما هو
  /// ليعيد المستخدم المحاولة، ويظهر سبب الخطأ.
  Future<void> _send() async {
    final text = _controller.text;
    if (_isSending || text.trim().isEmpty) return;
    final authState = ref.read(authStateProvider);
    final currentRole = authState is AuthAuthenticated ? authState.user.role : null;
    final inquiryType =
        currentRole == UserRole.doctor ? InquiryType.medical : _selectedInquiryType ?? InquiryType.technical;
    // حماية إضافية: المهندس لا يرسل في القناة الطبية (والـ backend يرفض أيضاً).
    if (currentRole == UserRole.engineer && inquiryType == InquiryType.medical) return;

    setState(() => _isSending = true);
    try {
      await ref.read(chatProvider(ChatConversation(widget.caseId, inquiryType)).notifier).send(text);
      // لا نمسح ما كتبه المستخدم أثناء الإرسال — فقط النص الذي أُرسل
      if (mounted && _controller.text == text) _controller.clear();
    } catch (e) {
      if (!mounted) return;
      // تغيّر مهندس العيادة أثناء فتح الشاشة: أعد جلب حق الرد ليظهر شريط القراءة فقط
      if (e is ApiException && e.statusCode == 403 && currentRole == UserRole.engineer) {
        ref.invalidate(replyRightsProvider(widget.caseId));
      }
      final reason = e is ApiException ? e.message : 'حدث خطأ غير متوقع';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إرسال الرسالة: $reason')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// أعلى المحادثة: زر لتحميل الرسائل الأقدم، أو مؤشر تحميل أثناء جلبها.
class _LoadOlderRow extends StatelessWidget {
  const _LoadOlderRow({required this.isLoading, required this.label, required this.onPressed});

  final bool isLoading;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              )
            : TextButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.history, size: 16, color: Colors.white70),
                label: Text(label, style: _Txt.readOnly),
              ),
      ),
    );
  }
}

class _InquiryTypePicker extends StatelessWidget {
  const _InquiryTypePicker({required this.onSelect});

  final ValueChanged<InquiryType> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('المحادثة', style: TextStyle(color: Colors.white)),
      ),
      body: _ChatGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر نوع الاستفسار',
                  textAlign: TextAlign.center,
                  style: _Txt.pickerTitle,
                ),
                const SizedBox(height: 10),
                const Text(
                  'يتم إرسال الاستفسار التقني إلى المهندس فقط، والطبي يصل إلى طبيبك.',
                  textAlign: TextAlign.center,
                  style: _Txt.pickerBody,
                ),
                const SizedBox(height: 28),
                _InquiryOption(
                  icon: Icons.settings_outlined,
                  title: InquiryType.technical.arabicLabel,
                  subtitle: 'يرسل إلى المهندس فقط',
                  onTap: () => onSelect(InquiryType.technical),
                ),
                const SizedBox(height: 14),
                _InquiryOption(
                  icon: Icons.medical_services_outlined,
                  title: InquiryType.medical.arabicLabel,
                  subtitle: 'تصل إلى طبيبك',
                  onTap: () => onSelect(InquiryType.medical),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InquiryOption extends StatelessWidget {
  const _InquiryOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: Colors.white),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _Txt.optionTitle),
                    const SizedBox(height: 2),
                    Text(subtitle, style: _Txt.optionSubtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientBanner extends StatelessWidget {
  const _RecipientBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: GlassContainer(
        borderRadius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(label, style: _Txt.banner),
      ),
    );
  }
}

class _ReadOnlyBar extends StatelessWidget {
  const _ReadOnlyBar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GlassContainer(
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _Txt.readOnly,
        ),
      ),
    );
  }
}
