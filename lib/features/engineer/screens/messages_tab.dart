import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/glass_container.dart';
import '../../chat/data/engineer_conversation_model.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../chat/logic/engineer_inbox_notifier.dart';
import '../../doctor/models/case_model.dart';

/// فلتر صندوق الرسائل: true = "My clinics" (الافتراضي)، false = "All".
/// خارج الـ widget حتى يبقى الاختيار عند التنقل بين التبويبات.
final inboxMineFilterProvider = StateProvider<bool>((ref) => true);

/// Messages tab — every engineer–patient (technical) conversation in one
/// place, instead of Devices → device → case → chat.
///
/// All engineers can read every conversation; only the responsible
/// engineer of the device's clinic can reply (rows show "Read only"
/// otherwise). Transparent on purpose — [EngineerHomeScreen] owns the
/// gradient background.
class MessagesTab extends ConsumerWidget {
  const MessagesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(inboxMineFilterProvider);
    final provider = engineerInboxProvider(mine);
    final state = ref.watch(provider);

    // عدّاد غير المقروء يُحدَّث كل 15 ثانية (أو فوراً عبر FCM): تغيّره يعني
    // رسالة جديدة أو قُرئت، فنحدّث القائمة بدل polling منفصل لها.
    ref.listen(unreadByCaseProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before != null && after != null && !mapEquals(before, after)) {
        ref.read(provider.notifier).refresh();
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: _FilterToggle(
              mine: mine,
              onChanged: (value) => ref.read(inboxMineFilterProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppGlassColors.baseDark,
              backgroundColor: Colors.white,
              onRefresh: () => ref.read(provider.notifier).refresh(),
              child: _buildBody(context, ref, state, mine),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, EngineerInboxState state, bool mine) {
    final notifier = ref.read(engineerInboxProvider(mine).notifier);
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (state.error != null && state.items.isEmpty) {
      return ErrorView(message: state.error.toString(), onRetry: notifier.refresh);
    }
    if (state.items.isEmpty) {
      return EmptyView(
        icon: Icons.forum_outlined,
        color: AppAccent.clinic,
        message: mine
            ? 'No messages from patients in your clinics yet'
            : 'No patient messages yet',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) notifier.loadMore();
        return false;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                ),
              ),
            );
          }
          final conversation = state.items[index];
          return _ConversationTile(
            conversation: conversation,
            onTap: () async {
              await context.push(
                '/engineer/chat/${conversation.caseId}',
                extra: conversation.replyRights,
              );
              // فتح المحادثة يعلّمها مقروءة (للمسؤول) — حدّث العدّادات
              notifier.refresh();
              ref.invalidate(unreadByCaseProvider);
            },
          );
        },
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.mine, required this.onChanged});
  final bool mine;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 14,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _segment('My messages', Icons.person_pin_circle_outlined, selected: mine, value: true),
          _segment('All', Icons.all_inbox_outlined, selected: !mine, value: false),
        ],
      ),
    );
  }

  Widget _segment(String label, IconData icon, {required bool selected, required bool value}) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: selected ? null : () => onChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? Colors.white : Colors.white54),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});
  final EngineerConversationModel conversation;
  final VoidCallback onTap;

  static Color _statusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.inTreatment:
        return Colors.greenAccent;
      case CaseStatus.closed:
        return Colors.white54;
    }
  }

  /// الوقت اليوم، "Yesterday"، أو التاريخ — بلا اعتماد على intl.
  static String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    String two(int n) => n.toString().padLeft(2, '0');
    if (day == today) return '${two(time.hour)}:${two(time.minute)}';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final hasUnread = c.unreadCount > 0;
    final statusColor = _statusColor(c.caseStatus);
    final details = [
      if (c.deviceSerial != null) c.deviceSerial!,
      c.clinicName ?? 'No clinic',
    ].join(' • ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: GlassContainer(
          opacity: hasUnread ? 0.16 : 0.10,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: Icons.person_outline, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.patientName, style: AppText.tileTitle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(c.lastMessageAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: hasUnread ? AppAccent.clinic : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(details, style: AppText.tileSubtitle),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.lastMessageText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: c.unreadCount),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Pill(label: c.caseStatus.label, color: statusColor),
                        if (c.responsibleEngineerName != null)
                          _Pill(label: 'Eng. ${c.responsibleEngineerName}', color: AppAccent.clinic),
                        if (!c.canReply)
                          const _Pill(label: 'Read only', color: Colors.white54, icon: Icons.visibility_outlined),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppAccent.unlinked,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Plain Container instead of Chip — see the note in devices_tab.dart.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
