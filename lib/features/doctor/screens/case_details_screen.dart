import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../../core/widgets/sessions_vs_attacks_chart.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../patient/models/session_model.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';
import '../models/case_progress_note_model.dart';

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

/// Category accent colors — every screen picks its palette from here so
/// data reads by color instead of a flat, uniform white.
class _Accent {
  static const Color doctor = Color(0xFF5AC8FA);
  static const Color patient = Color(0xFF34D399);
  static const Color caseC = Color(0xFFFBBF24);
  static const Color device = Color(0xFFA78BFA);
  static const Color unlinked = Color(0xFFF87171);
  static const Color clinic = Color(0xFF22D3EE);
}

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const headline = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
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
  static const sectionSubtitle = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
  static const body = TextStyle(color: Colors.white, fontSize: 14);
  static const label = TextStyle(color: Colors.white54, fontSize: 13);
  static const tileTitle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white60, fontSize: 12);
  static const error = TextStyle(color: Color(0xFFF87171));
}

/// Small circular badge behind a data-category icon: tinted fill,
/// tinted border, colored icon — replaces flat white avatars/icons.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Unified section header: colored side bar + small icon + white title
/// + a lighter subtitle line (which may contain a glowing highlight,
/// e.g. a count).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.subtitleSpans,
    this.subtitleText,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<InlineSpan>? subtitleSpans;
  final String? subtitleText;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitleSpans != null || subtitleText != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: hasSubtitle ? 34 : 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Txt.sectionTitleMedium),
              if (hasSubtitle) ...[
                const SizedBox(height: 2),
                subtitleSpans != null
                    ? Text.rich(TextSpan(style: _Txt.sectionSubtitle, children: subtitleSpans))
                    : Text(subtitleText!, style: _Txt.sectionSubtitle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A field label with a small colored leading icon, used above every
/// editable field on this screen instead of a plain white caption.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.icon, this.color = _Accent.doctor});
  final String text;
  final IconData? icon;
  final Color color;

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
              _IconBadge(icon: icon, color: color, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: isError ? _Txt.error : _Txt.hint)),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerStart, child: _RetryButton(onPressed: onRetry!)),
          ],
        ],
      ),
    );
  }
}

/// Glass-styled retry button used by every empty/error state.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
      label: const Text('Retry', style: TextStyle(color: Colors.white)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
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
/// plan / initial evaluation, and lists the case's logged sessions.
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
  final _newProgressNoteController = TextEditingController();
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _isAddingProgressNote = false;

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
    _newProgressNoteController.dispose();
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

  Future<void> _addProgressNote() async {
    final text = _newProgressNoteController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isAddingProgressNote = true);
    try {
      await ref.read(doctorRepositoryProvider).createProgressNote(
            NewCaseProgressNotePayload(caseId: widget.caseModel.id, note: text),
          );
      ref.invalidate(caseProgressNotesProvider(widget.caseModel.id));
      _newProgressNoteController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isAddingProgressNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.caseModel;
    final sessionsAsync = ref.watch(caseSessionsProvider(c.id));
    final progressNotesAsync = ref.watch(caseProgressNotesProvider(c.id));
    final weeklyEpisodeLogsAsync = ref.watch(caseWeeklyEpisodeLogsProvider(c.id));
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
                        color: _Accent.caseC,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        icon: Icons.event_note_outlined,
                        label: 'Sessions recorded',
                        value: '${c.completedSessionsCount}',
                        color: _Accent.patient,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- Read-only summary ---
                _SectionHeader(
                  icon: Icons.info_outline,
                  color: _Accent.caseC,
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
                      if (c.diagnosisType.hasClinicalDetails) ...[
                        _InfoRow(
                          label: 'attack / month',
                          value: c.monthlyEpisodeCount?.toString() ?? '—',
                        ),
                        _InfoRow(
                          label: 'attack duration',
                          value: c.episodeDurationMinutes != null
                              ? '${c.episodeDurationMinutes} min'
                              : '—',
                        ),
                        _InfoRow(
                          label: 'Medications',
                          value: c.currentMedications.isNotEmpty ? c.currentMedications : '—',
                        ),
                      ],
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
                _SectionHeader(
                  icon: Icons.edit_outlined,
                  color: _Accent.doctor,
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
                  data: (sessions) => _SectionHeader(
                    icon: Icons.history_outlined,
                    color: _Accent.patient,
                    title: 'Session History',
                    subtitleSpans: [
                      TextSpan(
                        text: '${sessions.length}',
                        style: TextStyle(
                          color: _Accent.patient,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          shadows: [
                            Shadow(color: _Accent.patient.withValues(alpha: 0.55), blurRadius: 14),
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
                    color: _Accent.unlinked,
                    message: 'Failed to load sessions: $e',
                    isError: true,
                    onRetry: () => ref.invalidate(caseSessionsProvider(c.id)),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return _InlineStatePanel(
                        icon: Icons.event_busy_outlined,
                        color: _Accent.patient,
                        message: 'No sessions logged yet for this case.',
                      );
                    }
                    final sorted = [...sessions]
                      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
                    return _SessionsGroup(sessions: sorted);
                  },
                ),

                const SizedBox(height: 28),
                _SectionHeader(
                  icon: Icons.show_chart_outlined,
                  color: _Accent.caseC,
                  title: 'Sessions vs Attacks',
                  subtitleText:
                      'Compares how many sessions were done against how many attacks were '
                      'reported over time, to visually see whether attacks are trending down.',
                ),
                const SizedBox(height: 10),
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  error: (e, _) => _InlineStatePanel(
                    icon: Icons.error_outline,
                    color: _Accent.unlinked,
                    message: 'Failed to load sessions: $e',
                    isError: true,
                    onRetry: () => ref.invalidate(caseSessionsProvider(c.id)),
                  ),
                  data: (sessions) => weeklyEpisodeLogsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                    error: (e, _) => _InlineStatePanel(
                      icon: Icons.error_outline,
                      color: _Accent.unlinked,
                      message: 'Failed to load weekly attack reports: $e',
                      isError: true,
                      onRetry: () => ref.invalidate(caseWeeklyEpisodeLogsProvider(c.id)),
                    ),
                    data: (episodeLogs) {
                      if (episodeLogs.isEmpty) {
                        return _InlineStatePanel(
                          icon: Icons.bar_chart_outlined,
                          color: _Accent.caseC,
                          message:
                              'No weekly attack reports from the patient yet — the chart '
                              'will appear once the patient starts answering the mandatory '
                              'weekly report.',
                        );
                      }
                      return GlassContainer(
                        padding: const EdgeInsets.all(12),
                        child: SessionsVsAttacksChart(sessions: sessions, episodeLogs: episodeLogs),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 28),
                progressNotesAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (notes) => _SectionHeader(
                    icon: Icons.notes_outlined,
                    color: _Accent.device,
                    title: 'Progress Notes',
                    subtitleSpans: [
                      TextSpan(
                        text: '${notes.length}',
                        style: TextStyle(
                          color: _Accent.device,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          shadows: [
                            Shadow(color: _Accent.device.withValues(alpha: 0.55), blurRadius: 14),
                          ],
                        ),
                      ),
                      const TextSpan(text: ' notes recorded'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Record what you observe at each follow-up exam (e.g. "after 5 of 15 sessions...")',
                  style: _Txt.hint,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _newProgressNoteController,
                  maxLines: 3,
                  style: _Txt.body,
                  cursorColor: Colors.white,
                  decoration: _fieldDecoration(hint: 'Describe the progress observed at this exam...'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                    ),
                    onPressed: _isAddingProgressNote ? null : _addProgressNote,
                    icon: _isAddingProgressNote
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add_circle_outline),
                    label: const Text('Add Progress Note'),
                  ),
                ),
                const SizedBox(height: 16),
                progressNotesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  error: (e, _) => _InlineStatePanel(
                    icon: Icons.error_outline,
                    color: _Accent.unlinked,
                    message: 'Failed to load progress notes: $e',
                    isError: true,
                    onRetry: () => ref.invalidate(caseProgressNotesProvider(c.id)),
                  ),
                  data: (notes) {
                    if (notes.isEmpty) {
                      return _InlineStatePanel(
                        icon: Icons.notes_outlined,
                        color: _Accent.device,
                        message: 'No progress notes recorded yet.',
                      );
                    }
                    return _ProgressNotesGroup(notes: notes);
                  },
                ),
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
          _IconBadge(icon: icon, color: color, size: 34),
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

/// All logged sessions grouped inside a single glass panel, separated by
/// thin translucent dividers instead of one card per session.
class _SessionsGroup extends StatelessWidget {
  const _SessionsGroup({required this.sessions});
  final List<SessionModel> sessions;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            _SessionTile(session: sessions[i]),
            if (i != sessions.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    final date = session.sessionDate;
    final dateLabel =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    final completed = session.patientResponse.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(
            icon: completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: completed ? _Accent.patient : Colors.white38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel, style: _Txt.tileTitle),
                const SizedBox(height: 2),
                if (session.patientResponse.isNotEmpty)
                  Text(
                    'Patient feedback: ${session.patientResponse}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  )
                else
                  const Text('No feedback submitted', style: _Txt.hint),
                if (session.durationMinutes != null)
                  Text('Duration: ${session.durationMinutes} min', style: _Txt.hint),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// All progress notes grouped inside a single glass panel, separated by
/// thin translucent dividers instead of one card per note.
class _ProgressNotesGroup extends StatelessWidget {
  const _ProgressNotesGroup({required this.notes});
  final List<CaseProgressNoteModel> notes;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < notes.length; i++) ...[
            _ProgressNoteTile(note: notes[i]),
            if (i != notes.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProgressNoteTile extends StatelessWidget {
  const _ProgressNoteTile({required this.note});
  final CaseProgressNoteModel note;

  @override
  Widget build(BuildContext context) {
    final date = note.createdAt;
    final dateLabel =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    final sessionsLabel = note.totalSessionsPlannedSnapshot != null
        ? '${note.sessionsCompletedSnapshot} / ${note.totalSessionsPlannedSnapshot} sessions'
        : '${note.sessionsCompletedSnapshot} sessions';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: Icons.sticky_note_2_outlined, color: _Accent.device),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(dateLabel, style: _Txt.tileTitle),
                    Text(sessionsLabel, style: _Txt.hint),
                  ],
                ),
                if (note.authorName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Dr. ${note.authorName}', style: _Txt.hint),
                ],
                const SizedBox(height: 6),
                Text(note.note, style: _Txt.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}