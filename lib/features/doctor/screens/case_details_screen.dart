import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/ltr_scope.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../patient/models/session_model.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';

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
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _status = widget.caseModel.status;
    _treatmentPlanController = TextEditingController(text: widget.caseModel.treatmentPlan);
    _initialEvaluationController = TextEditingController(text: widget.caseModel.initialEvaluation);
    _treatmentPlanController.addListener(_markChanged);
    _initialEvaluationController.addListener(_markChanged);
  }

  void _markChanged() {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  @override
  void dispose() {
    _treatmentPlanController.dispose();
    _initialEvaluationController.dispose();
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
            // --- Read-only summary ---
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(label: 'Diagnosis', value: c.diagnosisType.label),
                    _InfoRow(label: 'Device', value: c.deviceTypeName ?? '—'),
                    if (c.diagnosisType.hasClinicalDetails) ...[
                      _InfoRow(
                        label: 'Episodes / week',
                        value: c.weeklyEpisodeCount?.toString() ?? '—',
                      ),
                      _InfoRow(
                        label: 'Episode duration',
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

            // --- Guarantor info (read-only) ---
            if (c.guarantorName.isNotEmpty || c.guarantorPhoneNumber.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Guarantor', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _InfoRow(label: 'Name', value: c.guarantorName.isNotEmpty ? c.guarantorName : '—'),
                      _InfoRow(
                        label: 'Phone',
                        value: c.guarantorPhoneNumber.isNotEmpty ? c.guarantorPhoneNumber : '—',
                      ),
                      _InfoRow(
                        label: 'Address',
                        value: c.guarantorAddress.isNotEmpty ? c.guarantorAddress : '—',
                      ),
                      _InfoRow(
                        label: 'Email',
                        value: c.guarantorEmail.isNotEmpty ? c.guarantorEmail : '—',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

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
          ],
        ),
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