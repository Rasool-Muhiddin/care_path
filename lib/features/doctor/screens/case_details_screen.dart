import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../../core/widgets/session_calendar.dart';
import '../../attack_stats/attack_statistics_screen.dart';
import '../../case_summary/case_summary_section.dart';
import '../../chat/logic/chat_notifier.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';
import 'edit_case_sheet.dart';

/// Number of calendar days since [createdAt], counting the registration
/// day itself as day 1.
///
/// Using `DateTime.now().difference(createdAt).inDays` compares raw
/// 24-hour durations, not calendar dates — a patient registered at
/// 8 PM Monday and checked at 9 AM Wednesday has only ~37 hours elapsed
/// (`.inDays` == 1), even though that spans 3 calendar days. Since one
/// session is allowed per calendar day, that mismatch is exactly why the
/// sessions count could exceed "days since registration". Comparing
/// date-only values (dropping the time-of-day) and adding 1 fixes it.
int _daysSinceRegistration(DateTime createdAt) {
  final today = DateTime.now();
  final startDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final currentDate = DateTime(today.year, today.month, today.day);
  return currentDate.difference(startDate).inDays + 1;
}

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const sectionTitleMedium = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
}

/// Compact inline empty/error panel used for sections nested inside the
/// scroll view (not full-screen states): icon badge + message, with an
/// optional glass "Retry" action.
class _InlineStatePanel extends StatelessWidget {
  const _InlineStatePanel({
    required this.icon,
    required this.color,
    required this.message,
    this.onRetry,
    this.isError = false,
  });

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback? onRetry;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, color: color, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: isError ? AppText.error : _Txt.hint)),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerStart, child: RetryButton(onPressed: onRetry!)),
          ],
        ],
      ),
    );
  }
}

/// Case details screen — opened by tapping a case in the doctor's home
/// screen. Shows full case info and the case's sessions on a calendar; the
/// AppBar pencil opens the edit form (status / sessions planned / initial
/// evaluation / treatment plan) in a bottom sheet.
class CaseDetailsScreen extends ConsumerStatefulWidget {
  const CaseDetailsScreen({super.key, required this.caseModel});

  final CaseModel caseModel;

  @override
  ConsumerState<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends ConsumerState<CaseDetailsScreen> {
  /// The latest saved version of the case (replaced after an edit).
  late CaseModel _case = widget.caseModel;

  Future<void> _edit() async {
    final updated = await showEditCaseSheet(context, _case);
    if (updated == null || !mounted) return;
    setState(() => _case = updated);
    ref.invalidate(myCasesProvider);
    ref.invalidate(caseSessionsProvider(updated.id));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changes saved')));
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    final sessionsAsync = ref.watch(caseSessionsProvider(c.id));
    final unreadByCase = ref.watch(unreadByCaseProvider).value ?? {};
    final unreadForThisCase = unreadByCase[c.id] ?? 0;

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Case Details', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: 'Edit case',
              onPressed: _edit,
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: unreadForThisCase > 0,
                label: Text('$unreadForThisCase'),
                child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              ),
              tooltip: 'Chat with patient',
              onPressed: () => context.push('/doctor/chat/${c.id}'),
            ),
          ],
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Full patient name here (wraps) — the AppBar title is one line only.
                Text(
                  c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}',
                  style: AppText.headline,
                ),
                const SizedBox(height: 12),
                // --- Quick stats: days since registration & sessions
                // recorded, shown prominently at the top so the doctor sees
                // this at a glance for every case (same key numbers the
                // patient tracks about their own case). ---
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        icon: Icons.calendar_today_outlined,
                        label: 'Days since registration',
                        value: '${_daysSinceRegistration(c.createdAt)}',
                        color: AppAccent.caseC,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        icon: Icons.event_note_outlined,
                        label: 'Sessions recorded',
                        value: '${c.completedSessionsCount}',
                        color: AppAccent.patient,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- Read-only summary ---
                const SectionHeader(
                  titleStyle: _Txt.sectionTitleMedium,
                  icon: Icons.info_outline,
                  color: AppAccent.caseC,
                  title: 'Case Summary',
                ),
                const SizedBox(height: 10),
                CaseSummarySection(caseModel: c, sessionsProvider: caseSessionsProvider(c.id)),

                const SizedBox(height: 28),
                sessionsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (sessions) => SectionHeader(
                    titleStyle: _Txt.sectionTitleMedium,
                    icon: Icons.history_outlined,
                    color: AppAccent.patient,
                    title: 'Session History',
                    subtitleSpans: [
                      TextSpan(
                        text: '${sessions.length}',
                        style: TextStyle(
                          color: AppAccent.patient,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          shadows: [
                            Shadow(color: AppAccent.patient.withValues(alpha: 0.55), blurRadius: 14),
                          ],
                        ),
                      ),
                      const TextSpan(text: ' sessions logged'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  error: (e, _) => _InlineStatePanel(
                    icon: Icons.error_outline,
                    color: AppAccent.unlinked,
                    message: 'Failed to load sessions: $e',
                    isError: true,
                    onRetry: () => ref.invalidate(caseSessionsProvider(c.id)),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const _InlineStatePanel(
                        icon: Icons.event_busy_outlined,
                        color: AppAccent.patient,
                        message: 'No sessions logged yet for this case.',
                      );
                    }
                    return SessionCalendar(
                      sessions: sessions,
                      strings: SessionCalendarStrings.en,
                    );
                  },
                ),

                const SizedBox(height: 28),
                const SectionHeader(
                  titleStyle: _Txt.sectionTitleMedium,
                  icon: Icons.bolt_outlined,
                  color: AppAccent.caseC,
                  title: 'Attacks',
                  subtitleText: 'Attacks logged by the patient. The detailed statistics compare them '
                      'with sessions over any period.',
                ),
                const SizedBox(height: 10),
                AttackSummaryCard(caseModel: c, sessionsProvider: caseSessionsProvider(c.id)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        children: [
          IconBadge(icon: icon, color: color, size: 34),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 14)],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: _Txt.hint),
        ],
      ),
    );
  }
}
