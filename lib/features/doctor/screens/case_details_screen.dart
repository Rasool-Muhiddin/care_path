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
                        value: '${DateTime.now().difference(c.createdAt).inDays}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        icon: Icons.event_note_outlined,
                        label: 'Sessions recorded',
                        value: '${c.completedSessionsCount}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Read-only summary ---
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
                const SizedBox(height: 16),

                // --- Editable section ---
                const Text('Status', style: _Txt.sectionTitle),
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

                const Text('Total Sessions Planned', style: _Txt.sectionTitle),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _totalSessionsController,
                  keyboardType: TextInputType.number,
                  style: _Txt.body,
                  cursorColor: Colors.white,
                  decoration: _fieldDecoration(hint: 'e.g. 20'),
                ),
                const SizedBox(height: 20),

                const Text('Initial Evaluation', style: _Txt.sectionTitle),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _initialEvaluationController,
                  maxLines: 3,
                  style: _Txt.body,
                  cursorColor: Colors.white,
                  decoration: _fieldDecoration(),
                ),
                const SizedBox(height: 20),

                const Text('Treatment Plan', style: _Txt.sectionTitle),
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
                const Text('Session History', style: _Txt.sectionTitleMedium),
                const SizedBox(height: 8),
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Failed to load sessions: $e',
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No sessions logged yet for this case.', style: _Txt.hint),
                      );
                    }
                    final sorted = [...sessions]
                      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
                    return Column(
                      children: sorted.map((s) => _SessionTile(session: s)).toList(),
                    );
                  },
                ),

                const SizedBox(height: 28),
                const Text('Sessions vs Attacks', style: _Txt.sectionTitleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Compares how many sessions were done against how many attacks were '
                  'reported over time, to visually see whether attacks are trending down.',
                  style: _Txt.hint,
                ),
                const SizedBox(height: 8),
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Failed to load sessions: $e',
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                  data: (sessions) => weeklyEpisodeLogsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Failed to load weekly attack reports: $e',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    data: (episodeLogs) {
                      if (episodeLogs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'No weekly attack reports from the patient yet — the chart '
                            'will appear once the patient starts answering the mandatory '
                            'weekly report.',
                            style: _Txt.hint,
                          ),
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
                const Text('Progress Notes', style: _Txt.sectionTitleMedium),
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
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Failed to load progress notes: $e',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  data: (notes) {
                    if (notes.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No progress notes recorded yet.', style: _Txt.hint),
                      );
                    }
                    return Column(
                      children: notes.map((n) => _ProgressNoteTile(note: n)).toList(),
                    );
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
  const _StatBox({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
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

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dateLabel,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          session.patientResponse.isNotEmpty ? Icons.check_circle : Icons.radio_button_unchecked,
          color: session.patientResponse.isNotEmpty ? Colors.greenAccent : Colors.white38,
        ),
        title: Text(dateLabel, style: const TextStyle(color: Colors.white)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
        isThreeLine: session.durationMinutes != null,
      ),
    );
  }
}