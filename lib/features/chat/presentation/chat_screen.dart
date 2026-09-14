import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/ltr_scope.dart'; // عدّل المسار إذا كان مختلفًا
import '../../../core/auth/auth_state.dart';
import '../../../core/permissions/user_role.dart';
import '../logic/chat_notifier.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int caseId;
  const ChatScreen({super.key, required this.caseId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(widget.caseId));
    final authState = ref.watch(authStateProvider);
    final currentRole = authState is AuthAuthenticated ? authState.user.role : null;
    final isStaff = currentRole == UserRole.doctor || currentRole == UserRole.engineer;

    final content = Scaffold(
      appBar: AppBar(title: Text(isStaff ? 'Conversation' : 'المحادثة')),
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

    return isStaff ? LtrScope(child: content) : content;
  }

  void _send() {
    final text = _controller.text;
    _controller.clear();
    ref.read(chatProvider(widget.caseId).notifier).send(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}