import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ltr_scope.dart';
import '../../../core/widgets/sessions_vs_attacks_chart.dart';
import '../../doctor/models/case_model.dart';
import '../engineer_providers.dart';

/// صفحة تفاصيل مريض عند المهندس (للقراءة فقط) — تُفتح بالضغط على المريض
/// في لوحة المتابعة، وتعرض ملخص حالته والشارت (جلسات مقابل نوبات).
class EngineerPatientDetailsScreen extends ConsumerWidget {
  const EngineerPatientDetailsScreen({super.key, required this.caseModel});

  final CaseModel caseModel;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(engineerCaseSessionsProvider(caseModel.id));
    ref.invalidate(engineerCaseWeeklyEpisodeLogsProvider(caseModel.id));
    await Future.wait([
      ref.read(engineerCaseSessionsProvider(caseModel.id).future),
      ref.read(engineerCaseWeeklyEpisodeLogsProvider(caseModel.id).future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = caseModel;
    final sessionsAsync = ref.watch(engineerCaseSessionsProvider(c.id));
    final logsAsync = ref.watch(engineerCaseWeeklyEpisodeLogsProvider(c.id));

    return LtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}'),
        ),
        body: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Status', value: c.status.label),
                      _InfoRow(label: 'Diagnosis', value: c.diagnosisType.label),
                      _InfoRow(label: 'Device', value: c.deviceTypeName ?? '—'),
                      _InfoRow(
                        label: 'Sessions completed',
                        value: c.remainingSessionsCount != null
                            ? '${c.completedSessionsCount} / ${c.totalSessionsPlanned} (${c.remainingSessionsCount} left)'
                            : '${c.completedSessionsCount}',
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
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('Sessions vs Attacks', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Compares how many sessions were done against how many attacks were '
                'reported over time.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              sessionsAsync.when(
                loading: _loading,
                error: (e, _) => _error('Failed to load sessions: $e'),
                data: (sessions) => logsAsync.when(
                  loading: _loading,
                  error: (e, _) => _error('Failed to load weekly attack reports: $e'),
                  data: (logs) {
                    if (logs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No weekly attack reports from the patient yet.'),
                      );
                    }
                    return SessionsVsAttacksChart(sessions: sessions, episodeLogs: logs);
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _loading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );

  static Widget _error(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: const TextStyle(color: Colors.red)),
      );
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
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
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