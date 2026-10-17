import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/attacks/attack_repository.dart';
import '../../core/attacks/attack_stats.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/baghdad_time.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/glass_container.dart';
import '../doctor/models/case_model.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) {
  final b = toBaghdad(d);
  return '${b.year}/${_two(b.month)}/${_two(b.day)}';
}

String _orDash(String? s) => (s == null || s.trim().isEmpty) ? '—' : s.trim();

class _Txt {
  static const groupTitle = TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700);
  static const label = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const value = TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500);
  static const caption = TextStyle(color: Colors.white54, fontSize: 12);
}

/// Full case information for the doctor and the engineer (English, LTR),
/// split into "Before treatment" (the patient's condition at registration
/// — the baseline) and "Current" (treatment, device and this month's
/// attacks). Every rate or duration field is labelled "Average".
///
/// Treatment starts when the case is created (no separate start event).
class CaseSummarySection extends ConsumerWidget {
  const CaseSummarySection({super.key, required this.caseModel});

  final CaseModel caseModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = caseModel;
    final isMigraine = c.diagnosisType == DiagnosisType.migraine;
    final attacks = ref.watch(caseAttacksProvider(c.id));

    final sessionsValue = c.totalSessionsPlanned != null
        ? '${c.completedSessionsCount} of ${c.totalSessionsPlanned} '
            '(${c.remainingSessionsCount ?? 0} remaining)'
        : '${c.completedSessionsCount} (no total planned)';

    PeriodStats? thisMonth;
    if (attacks.hasValue) {
      thisMonth = AttackAnalysis(
        caseCreatedAt: c.createdAt,
        sessions: const [],
        attacks: attacks.value!,
        confirmations: const [],
      ).calendarMonth(0);
    }
    final attackLoading = attacks.isLoading ? '…' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Part(
          icon: Icons.history_toggle_off,
          color: AppAccent.caseC,
          title: 'Before treatment',
          caption: 'The patient\'s condition at registration',
          children: [
            _Row('Diagnosis', c.diagnosisType.label),
            _Row('${c.diagnosisType.label} type', diseaseTypeLabel(c.diagnosisType, c.diseaseType)),
            _Row('Average attacks / month', c.monthlyEpisodeCount?.toString() ?? '—'),
            _Row(
              'Average attack duration',
              c.episodeDurationMinutes != null ? formatAttackDuration(c.episodeDurationMinutes! * 60) : '—',
            ),
            _Row('Symptoms', _orDash(c.symptoms)),
            _Row('Medications', _orDash(c.currentMedications)),
            _Row('Initial evaluation', _orDash(c.initialEvaluation)),
            _Row('Registered', _date(c.createdAt)),
          ],
        ),
        const SizedBox(height: 12),
        _Part(
          icon: Icons.monitor_heart_outlined,
          color: AppAccent.patient,
          title: 'Current',
          caption: 'Since the case was created — treatment starts on that day.',
          children: [
            _Row('Status', c.status.label),
            _Row('Doctor', _orDash(c.doctorName)),
            _Row('Supervising Engineer', c.responsibleEngineerName?.trim().isNotEmpty == true
                ? c.responsibleEngineerName!.trim()
                : 'Not assigned'),
            _Row('Treatment start', _date(c.createdAt)),
            _Row('Sessions completed', sessionsValue),
            _Row('Treatment plan', _orDash(c.treatmentPlan)),
            _Row('Device', _orDash(c.deviceTypeName)),
            _Row('Device serial number', _orDash(c.deviceSerialNumber)),
            _Row('Clinic', _orDash(c.clinicName)),
            const _SubTitle('Attacks this month'),
            _Row('Attacks', thisMonth != null ? '${thisMonth.attackCount}' : attackLoading),
            _Row(
              'Average attack duration',
              thisMonth?.avgDurationSeconds != null
                  ? formatAttackDuration(thisMonth!.avgDurationSeconds!)
                  : (thisMonth != null ? '—' : attackLoading),
            ),
            if (isMigraine)
              _Row(
                'Average severity',
                thisMonth?.avgSeverity != null
                    ? '${thisMonth!.avgSeverity!.toStringAsFixed(1)} / 10'
                    : (thisMonth != null ? '—' : attackLoading),
              ),
            const SizedBox(height: 4),
            _Row('Last updated', _date(c.updatedAt)),
          ],
        ),
      ],
    );
  }
}

class _Part extends StatelessWidget {
  const _Part({
    required this.icon,
    required this.color,
    required this.title,
    required this.caption,
    required this.children,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(caption, style: _Txt.caption),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(text, style: _Txt.groupTitle),
      );
}

/// Label + value side by side; both wrap (never truncated), the label
/// column takes 2/5 of the width so long labels like "Average attack
/// duration" fit on narrow phones and with large system fonts.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: _Txt.label)),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: Text(value, style: _Txt.value)),
        ],
      ),
    );
  }
}
