import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../../core/widgets/sessions_vs_attacks_chart.dart';
import '../../doctor/models/case_model.dart';
import '../engineer_providers.dart';

/// Accent palette — mirrors the one used in OverviewTab so a patient's
/// stats/info read consistently with the rest of the engineer section.
class _Accent {
  static const days = Color(0xFF5AC8FA);
  static const sessions = Color(0xFF34D399);
  static const status = Color(0xFFFBBF24);
  static const chart = Color(0xFFA78BFA);
}

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700);
  static const sectionSubtitle = TextStyle(color: Colors.white54, fontSize: 12);
  static const label = TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w500);
  static const value = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);
  static const statValue = TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800);
  static const statLabel = TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500);
  static const error = TextStyle(color: Colors.redAccent, fontSize: 13);
  static const empty = TextStyle(color: Colors.white54, fontSize: 13);

  static List<Shadow> glow(Color color, {double blur = 14}) => [
        Shadow(color: color.withValues(alpha: 0.55), blurRadius: blur),
      ];
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
                          icon: Icons.calendar_today_rounded,
                          accent: _Accent.days,
                          label: 'Days since registration',
                          value: '${DateTime.now().difference(c.createdAt).inDays}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBox(
                          icon: Icons.event_note_rounded,
                          accent: _Accent.sessions,
                          label: 'Sessions recorded',
                          value: '${c.completedSessionsCount}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(
                    icon: Icons.badge_outlined,
                    accent: _Accent.status,
                    title: 'Case summary',
                  ),
                  const SizedBox(height: 10),
                  GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Column(
                      children: [
                        _InfoRow(icon: Icons.flag_rounded, label: 'Status', value: c.status.label),
                        _divider(),
                        _InfoRow(icon: Icons.psychology_alt_outlined, label: 'Diagnosis', value: c.diagnosisType.label),
                        _divider(),
                        _InfoRow(icon: Icons.memory_rounded, label: 'Device', value: c.deviceTypeName ?? '—'),
                        _divider(),
                        _InfoRow(
                          icon: Icons.fact_check_outlined,
                          label: 'Sessions completed',
                          value: c.remainingSessionsCount != null
                              ? '${c.completedSessionsCount} / ${c.totalSessionsPlanned} (${c.remainingSessionsCount} left)'
                              : '${c.completedSessionsCount}',
                        ),
                        if (c.diagnosisType.hasClinicalDetails) ...[
                          _divider(),
                          _InfoRow(
                            icon: Icons.bolt_rounded,
                            label: 'attack / month',
                            value: c.monthlyEpisodeCount?.toString() ?? '—',
                          ),
                          _divider(),
                          _InfoRow(
                            icon: Icons.timer_outlined,
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
                  const _SectionHeader(
                    icon: Icons.bar_chart_rounded,
                    accent: _Accent.chart,
                    title: 'Sessions vs Attacks',
                    subtitle: 'Compares how many sessions were done against how many attacks '
                        'were reported over time.',
                  ),
                  const SizedBox(height: 10),
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

  static Widget _divider() => Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.08),
        indent: 16,
        endIndent: 16,
      );

  static Widget _loading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );

  static Widget _error(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: _Txt.error),
      );
}

/// A round icon badge tinted with [color] — mirrors OverviewTab's _IconBadge
/// so stat boxes and info rows carry the same category-color language.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.size = 34});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.accent, required this.title, this.subtitle});
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: subtitle != null ? 36 : 22,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8)],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Flexible(child: Text(title, style: _Txt.sectionTitle)),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: _Txt.sectionSubtitle),
                ],
              ],
            ),
          ),
        ],
      );
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.icon, required this.accent, required this.label, required this.value});
  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        children: [
          _IconBadge(icon: icon, color: accent),
          const SizedBox(height: 8),
          Text(value, style: _Txt.statValue.copyWith(shadows: _Txt.glow(accent))),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: _Txt.statLabel),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: Colors.white54),
          const SizedBox(width: 10),
          SizedBox(width: 118, child: Text(label, style: _Txt.label)),
          Expanded(child: Text(value, style: _Txt.value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}