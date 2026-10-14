import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../../core/widgets/session_calendar.dart';
import '../../attack_stats/attack_statistics_screen.dart';
import '../../chat/logic/chat_notifier.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';

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
  static const sectionTitle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const sectionTitleMedium = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
  static const body = TextStyle(color: Colors.white, fontSize: 14);
  static const label = TextStyle(color: Colors.white54, fontSize: 13);
}

/// A field label with a small colored leading icon, used above every
/// editable field on this screen instead of a plain white caption.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.icon});
  final String text;
  final IconData? icon;
  static const Color color = AppAccent.doctor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(text, style: _Txt.sectionTitle),
      ],
    );
  }
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

/// Reusable "field wrapped in a glass panel" [InputDecoration], used for
/// every [TextFormField]/[DropdownButtonFormField] on this screen so they
/// read consistently against the navy gradient background.
InputDecoration _fieldDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: _Txt.hint,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );
}

/// Case details screen — opened by tapping a case in the doctor's home
/// screen. Shows full case info, lets the doctor edit status / treatment
/// plan / initial evaluation, and shows the case's sessions on a calendar.
class CaseDetailsScreen extends ConsumerStatefulWidget {
  const CaseDetailsScreen({super.key, required this.caseModel});

  final CaseModel caseModel;

  @override
  ConsumerState<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends ConsumerState<CaseDetailsScreen> {
  late CaseStatus _status;
  late final TextEditingController _treatmentPlanController;
  late final TextEditingController _initialEvaluationController;
  late final TextEditingController _totalSessionsController;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _status = widget.caseModel.status;
    _treatmentPlanController = TextEditingController(text: widget.caseModel.treatmentPlan);
    _initialEvaluationController = TextEditingController(text: widget.caseModel.initialEvaluation);
    _totalSessionsController =
        TextEditingController(text: widget.caseModel.totalSessionsPlanned?.toString() ?? '');
    _treatmentPlanController.addListener(_markChanged);
    _initialEvaluationController.addListener(_markChanged);
    _totalSessionsController.addListener(_markChanged);
  }

  void _markChanged() {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  @override
  void dispose() {
    _treatmentPlanController.dispose();
    _initialEvaluationController.dispose();
    _totalSessionsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(doctorRepositoryProvider).updateCase(
            widget.caseModel.id,
            CaseUpdatePayload(
              status: _status,
              treatmentPlan: _treatmentPlanController.text.trim(),
              initialEvaluation: _initialEvaluationController.text.trim(),
              totalSessionsPlanned: int.tryParse(_totalSessionsController.text.trim()),
            ),
          );
      ref.invalidate(myCasesProvider);
      if (mounted) {
        setState(() => _hasUnsavedChanges = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Changes saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.caseModel;
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
          title: Text(
            c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
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
                SectionHeader(
                  titleStyle: _Txt.sectionTitleMedium,
                  icon: Icons.info_outline,
                  color: AppAccent.caseC,
                  title: 'Case Info',
                ),
                const SizedBox(height: 10),
                GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Diagnosis', value: c.diagnosisType.label),
                      _InfoRow(
                        label: '${c.diagnosisType.label} Type',
                        value: diseaseTypeLabel(c.diagnosisType, c.diseaseType),
                      ),
                      _InfoRow(label: 'Device', value: c.deviceTypeName ?? '—'),
                      _InfoRow(
                        label: 'Sessions completed',
                        value: c.remainingSessionsCount != null
                            ? '${c.completedSessionsCount} / ${c.totalSessionsPlanned} (${c.remainingSessionsCount} left)'
                            : '${c.completedSessionsCount}',
                      ),
                      _InfoRow(
                        label: 'Symptoms',
                        value: c.symptoms.isNotEmpty ? c.symptoms : '—',
                      ),
                      _InfoRow(
                        label: 'Baseline attacks / month',
                        value: c.monthlyEpisodeCount?.toString() ?? '—',
                      ),
                      _InfoRow(
                        label: 'Baseline attack duration',
                        value: c.episodeDurationMinutes != null
                            ? '${c.episodeDurationMinutes} min'
                            : '—',
                      ),
                      _InfoRow(
                        label: 'Medications',
                        value: c.currentMedications.isNotEmpty ? c.currentMedications : '—',
                      ),
                      _InfoRow(
                        label: 'Created',
                        value:
                            '${c.createdAt.year}/${c.createdAt.month.toString().padLeft(2, '0')}/${c.createdAt.day.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- Editable section ---
                SectionHeader(
                  titleStyle: _Txt.sectionTitleMedium,
                  icon: Icons.edit_outlined,
                  color: AppAccent.doctor,
                  title: 'Edit Case',
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Status', icon: Icons.flag_outlined),
                const SizedBox(height: 8),
                DropdownButtonFormField<CaseStatus>(
                  initialValue: _status,
                  decoration: _fieldDecoration(),
                  dropdownColor: AppGlassColors.baseDark,
                  style: _Txt.body,
                  iconEnabledColor: Colors.white70,
                  items: CaseStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _status = value!;
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 20),

                const _FieldLabel('Total Sessions Planned', icon: Icons.format_list_numbered),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _totalSessionsController,
                  keyboardType: TextInputType.number,
                  style: _Txt.body,
                  cursorColor: Colors.white,
                  decoration: _fieldDecoration(hint: 'e.g. 20'),
                ),
                const SizedBox(height: 20),

                const _FieldLabel('Initial Evaluation', icon: Icons.fact_check_outlined),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _initialEvaluationController,
                  maxLines: 3,
                  style: _Txt.body,
                  cursorColor: Colors.white,
                  decoration: _fieldDecoration(),
                ),
                const SizedBox(height: 20),

                const _FieldLabel('Treatment Plan', icon: Icons.assignment_outlined),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _treatmentPlanController,
                  maxLines: 3,
                  style: _Txt.body,
                  cursorColor: Colors.white,
                  decoration: _fieldDecoration(),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    ),
                    onPressed: (_isSaving || !_hasUnsavedChanges) ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),

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
                      return _InlineStatePanel(
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
                      'with sessions and with the before-treatment baseline.',
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: _Txt.label)),
          Expanded(child: Text(value, style: _Txt.body)),
        ],
      ),
    );
  }
}
