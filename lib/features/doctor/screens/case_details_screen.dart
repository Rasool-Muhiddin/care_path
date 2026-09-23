import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/ltr_scope.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../patient/models/session_model.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';
import '../models/case_progress_note_model.dart';
import '../models/weekly_episode_log_model.dart';

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
        appBar: AppBar(
          title: Text(c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}'),
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: unreadForThisCase > 0,
                label: Text('$unreadForThisCase'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              tooltip: 'Chat with patient',
              onPressed: () => context.push('/doctor/chat/${c.id}'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
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
            Card(
              child: Padding(
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
            ),
            const SizedBox(height: 16),

            // --- Editable section ---
            Text('Status', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<CaseStatus>(
              initialValue: _status,
              decoration: const InputDecoration(border: OutlineInputBorder()),
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

            Text('Total Sessions Planned', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _totalSessionsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. 20',
              ),
            ),
            const SizedBox(height: 20),

            Text('Initial Evaluation', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _initialEvaluationController,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            Text('Treatment Plan', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _treatmentPlanController,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            FilledButton(
              onPressed: (_isSaving || !_hasUnsavedChanges) ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),

            const SizedBox(height: 28),
            Text('Session History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            sessionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Failed to load sessions: $e', style: const TextStyle(color: Colors.red)),
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No sessions logged yet for this case.'),
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
            Text('Sessions vs Attacks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Compares how many sessions were done against how many attacks were '
              'reported over time, to visually see whether attacks are trending down.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            sessionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Failed to load sessions: $e', style: const TextStyle(color: Colors.red)),
              ),
              data: (sessions) => weeklyEpisodeLogsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Failed to load weekly attack reports: $e',
                    style: const TextStyle(color: Colors.red),
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
                      ),
                    );
                  }
                  return _SessionsVsAttacksChart(sessions: sessions, episodeLogs: episodeLogs);
                },
              ),
            ),

            const SizedBox(height: 28),
            Text('Progress Notes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Record what you observe at each follow-up exam (e.g. "after 5 of 15 sessions...")',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newProgressNoteController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe the progress observed at this exam...',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isAddingProgressNote ? null : _addProgressNote,
                icon: _isAddingProgressNote
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: const Text('Add Progress Note'),
              ),
            ),
            const SizedBox(height: 16),
            progressNotesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Failed to load progress notes: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              data: (notes) {
                if (notes.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No progress notes recorded yet.'),
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
    );
  }
}

enum _ChartGranularity { weekly, monthly }

/// Grouped bar chart comparing sessions done vs attacks reported, either
/// per week (each bar = one WeeklyEpisodeLog) or per calendar month
/// (4 weeks combined, as suggested) — toggled via the segmented control.
/// Attack counts come from WeeklyEpisodeLog (patient's mandatory weekly
/// reports), not from the old static Case.monthly_episode_count, since
/// only the weekly reports form an actual time series.
class _SessionsVsAttacksChart extends StatefulWidget {
  const _SessionsVsAttacksChart({required this.sessions, required this.episodeLogs});
  final List<SessionModel> sessions;
  final List<WeeklyEpisodeLogModel> episodeLogs;

  @override
  State<_SessionsVsAttacksChart> createState() => _SessionsVsAttacksChartState();
}

class _SessionsVsAttacksChartState extends State<_SessionsVsAttacksChart> {
  _ChartGranularity _granularity = _ChartGranularity.monthly;

  String _twoDigit(int n) => n.toString().padLeft(2, '0');

  /// Builds (label, sessionCount, attackCount) triples, sorted by time,
  /// one per week or one per calendar month depending on [_granularity].
  List<(String, double, double)> _buildBars() {
    final sortedLogs = [...widget.episodeLogs]
      ..sort((a, b) => a.weekStartDate.compareTo(b.weekStartDate));

    if (_granularity == _ChartGranularity.weekly) {
      return sortedLogs.map((log) {
        final weekEnd = log.weekStartDate.add(const Duration(days: 7));
        final sessionsInWeek = widget.sessions
            .where((s) =>
                !s.sessionDate.isBefore(log.weekStartDate) && s.sessionDate.isBefore(weekEnd))
            .length;
        final label = '${_twoDigit(log.weekStartDate.month)}/${_twoDigit(log.weekStartDate.day)}';
        return (label, sessionsInWeek.toDouble(), log.episodeCount.toDouble());
      }).toList();
    }

    // شهري: نجمع كل الأسابيع اللي تبدأ بنفس الشهر (سنة/شهر)، ونجمع
    // الجلسات حسب تاريخها الفعلي بنفس (سنة/شهر).
    final episodesByMonth = <String, int>{};
    final monthOrder = <String>[];
    for (final log in sortedLogs) {
      final key = '${log.weekStartDate.year}-${_twoDigit(log.weekStartDate.month)}';
      if (!episodesByMonth.containsKey(key)) monthOrder.add(key);
      episodesByMonth[key] = (episodesByMonth[key] ?? 0) + log.episodeCount;
    }
    final sessionsByMonth = <String, int>{};
    for (final s in widget.sessions) {
      final key = '${s.sessionDate.year}-${_twoDigit(s.sessionDate.month)}';
      sessionsByMonth[key] = (sessionsByMonth[key] ?? 0) + 1;
    }
    monthOrder.sort();
    return monthOrder
        .map((key) => (key, (sessionsByMonth[key] ?? 0).toDouble(), episodesByMonth[key]!.toDouble()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bars = _buildBars();
    final colorScheme = Theme.of(context).colorScheme;

    final maxY = bars.isEmpty
        ? 10.0
        : bars
            .map((b) => b.$2 > b.$3 ? b.$2 : b.$3)
            .reduce((a, b) => a > b ? a : b) *
            1.2 + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: colorScheme.primary, label: 'Sessions'),
            const SizedBox(width: 16),
            _LegendDot(color: colorScheme.error, label: 'Attacks'),
            const Spacer(),
            SegmentedButton<_ChartGranularity>(
              segments: const [
                ButtonSegment(value: _ChartGranularity.monthly, label: Text('Monthly')),
                ButtonSegment(value: _ChartGranularity.weekly, label: Text('Weekly')),
              ],
              selected: {_granularity},
              onSelectionChanged: (s) => setState(() => _granularity = s.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (bars.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Not enough data yet for this view.'),
          )
        else
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 28),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(bars[i].$1, style: Theme.of(context).textTheme.bodySmall),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < bars.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: bars[i].$2,
                          color: colorScheme.primary,
                          width: 10,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: bars[i].$3,
                          color: colorScheme.error,
                          width: 10,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                      barsSpace: 4,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(sessionsLabel, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (note.authorName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Dr. ${note.authorName}', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Text(note.note),
          ],
        ),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          session.patientResponse.isNotEmpty ? Icons.check_circle : Icons.radio_button_unchecked,
          color: session.patientResponse.isNotEmpty ? Colors.green : Colors.grey,
        ),
        title: Text(dateLabel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session.patientResponse.isNotEmpty)
              Text(
                'Patient feedback: ${session.patientResponse}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              )
            else
              const Text('No feedback submitted', style: TextStyle(color: Colors.grey)),
            if (session.durationMinutes != null)
              Text('Duration: ${session.durationMinutes} min'),
          ],
        ),
        isThreeLine: session.durationMinutes != null,
      ),
    );
  }
}