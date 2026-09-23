import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/ltr_scope.dart'; // عدّل المسار إذا كان مختلفًا
import '../../../core/auth/auth_state.dart';
import '../../../core/permissions/user_role.dart';
import '../data/chat_message_model.dart';
import '../logic/chat_notifier.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int caseId;
  const ChatScreen({super.key, required this.caseId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  InquiryType? _selectedInquiryType;

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

    final inquiryType = currentRole == UserRole.doctor
        ? InquiryType.medical
        : _selectedInquiryType ?? InquiryType.technical;
    final conversation = ChatConversation(widget.caseId, inquiryType);
    final state = ref.watch(chatProvider(conversation));

    final content = Scaffold(
      appBar: AppBar(
        title: Text(inquiryType.arabicLabel),
        leading: currentRole == UserRole.patient
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'تغيير نوع الاستفسار',
                onPressed: () => setState(() => _selectedInquiryType = null),
              )
            : null,
        actions: currentRole == UserRole.engineer
            ? [
                PopupMenuButton<InquiryType>(
                  tooltip: 'اختيار قناة المحادثة',
                  onSelected: (type) => setState(() => _selectedInquiryType = type),
                  itemBuilder: (context) => InquiryType.values
                      .map(
                        (type) => PopupMenuItem(
                          value: type,
                          child: Text(type.arabicLabel),
                        ),
                      )
                      .toList(),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.messages.length,
                    itemBuilder: (context, i) {
                      final msg = state.messages[i];
                      return Align(
                        alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: msg.isMine
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!msg.isMine)
                                Text(msg.senderName,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              Text(msg.text, style: TextStyle(color: msg.isMine ? Colors.white : null)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: isStaff ? 'Type a message...' : 'اكتب رسالة...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // تبقى واجهة المريض RTL؛ حسابات الكادر تستخدم الغلاف الموجود سابقاً.
    return isStaff ? LtrScope(child: content) : content;
  }

  void _send() {
    final text = _controller.text;
    _controller.clear();
    final authState = ref.read(authStateProvider);
    final currentRole = authState is AuthAuthenticated ? authState.user.role : null;
    final inquiryType = currentRole == UserRole.doctor
        ? InquiryType.medical
        : _selectedInquiryType ?? InquiryType.technical;
    ref
        .read(chatProvider(ChatConversation(widget.caseId, inquiryType)).notifier)
        .send(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _InquiryTypePicker extends StatelessWidget {
  const _InquiryTypePicker({required this.onSelect});

  final ValueChanged<InquiryType> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثة')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اختر نوع الاستفسار',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'يتم إرسال الاستفسار التقني إلى المهندس فقط، والطبي إلى المهندس وطبيبك.',
              textAlign: TextAlign.center,
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
              subtitle: 'يرسل إلى المهندس وطبيبك المعالج',
              onTap: () => onSelect(InquiryType.medical),
            ),
          ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
