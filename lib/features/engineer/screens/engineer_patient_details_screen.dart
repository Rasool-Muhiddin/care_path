import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../../core/widgets/sessions_vs_attacks_chart.dart';
import '../../doctor/models/case_model.dart';
import '../engineer_providers.dart';

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const title = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700);
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);
  static const sectionSubtitle = TextStyle(color: Colors.white70, fontSize: 12);
  static const label = TextStyle(color: Colors.white70, fontSize: 13);
  static const value = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500);
  static const statValue = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const statLabel = TextStyle(color: Colors.white70, fontSize: 11);
  static const error = TextStyle(color: Colors.redAccent, fontSize: 13);
  static const empty = TextStyle(color: Colors.white70, fontSize: 13);
}

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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(
            c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              color: Colors.white,
              backgroundColor: AppGlassColors.baseDark,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                  GlassContainer(
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
                  const SizedBox(height: 28),
                  const Text('Sessions vs Attacks', style: _Txt.sectionTitle),
                  const SizedBox(height: 4),
                  const Text(
                    'Compares how many sessions were done against how many attacks were '
                    'reported over time.',
                    style: _Txt.sectionSubtitle,
                  ),
                  const SizedBox(height: 8),
                  GlassContainer(
                    padding: const EdgeInsets.all(12),
                    child: sessionsAsync.when(
                      loading: _loading,
                      error: (e, _) => _error('Failed to load sessions: $e'),
                      data: (sessions) => logsAsync.when(
                        loading: _loading,
                        error: (e, _) => _error('Failed to load weekly attack reports: $e'),
                        data: (logs) {
                          if (logs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No weekly attack reports from the patient yet.',
                                style: _Txt.empty,
                              ),
                            );
                          }
                          return SessionsVsAttacksChart(sessions: sessions, episodeLogs: logs);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _loading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );

  static Widget _error(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: _Txt.error),
      );
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
          Text(value, style: _Txt.statValue),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: _Txt.statLabel),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: _Txt.label)),
          Expanded(child: Text(value, style: _Txt.value)),
        ],
      ),
    );
  }
}