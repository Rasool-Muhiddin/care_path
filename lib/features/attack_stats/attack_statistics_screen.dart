import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/attacks/attack_models.dart';
import '../../core/attacks/attack_repository.dart';
import '../../core/attacks/attack_stats.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/attack_list.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/widgets/ltr_scope.dart';
import '../../core/widgets/sessions_vs_attacks_chart.dart';
import '../doctor/models/case_model.dart';
import '../patient/models/session_model.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}/${_two(d.month)}/${_two(d.day)}';

class _Txt {
  static const title = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);
  static const label = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const value = TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600);
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
}

/// Detailed attack statistics for one case — shared by the doctor and the
/// engineer (English, LTR; the patient doesn't get this screen).
///
/// "Baseline (before treatment)" and "During treatment" are separate
/// sections and their numbers never mix: treatment starts on the Baghdad
/// day of the first treatment session.
class AttackStatisticsScreen extends ConsumerStatefulWidget {
  const AttackStatisticsScreen({
    super.key,
    required this.caseModel,
    required this.sessionsProvider,
  });

  final CaseModel caseModel;

  /// The role's own provider for this case's sessions (doctor/engineer).
  final AutoDisposeFutureProvider<List<SessionModel>> sessionsProvider;

  @override
  ConsumerState<AttackStatisticsScreen> createState() => _AttackStatisticsScreenState();
}

class _AttackStatisticsScreenState extends ConsumerState<AttackStatisticsScreen> {
  StatsGranularity _granularity = StatsGranularity.monthly;

  Future<void> _refresh() async {
    final id = widget.caseModel.id;
    ref.invalidate(widget.sessionsProvider);
    ref.invalidate(caseAttacksProvider(id));
    ref.invalidate(caseAttackConfirmationsProvider(id));
    await Future.wait([
      ref.read(widget.sessionsProvider.future),
      ref.read(caseAttacksProvider(id).future),
      ref.read(caseAttackConfirmationsProvider(id).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.caseModel;
    final sessions = ref.watch(widget.sessionsProvider);
    final attacks = ref.watch(caseAttacksProvider(c.id));
    final confirmations = ref.watch(caseAttackConfirmationsProvider(c.id));

    Widget body;
    final error = sessions.error ?? attacks.error ?? confirmations.error;
    if (error != null) {
      body = ErrorView(message: error.toString(), onRetry: _refresh);
    } else if (!sessions.hasValue || !attacks.hasValue || !confirmations.hasValue) {
      body = const Center(child: CircularProgressIndicator(color: Colors.white));
    } else {
      final analysis = AttackAnalysis(
        caseCreatedAt: c.createdAt,
        sessions: sessions.value!,
        attacks: attacks.value!,
        confirmations: confirmations.value!,
      );
      body = RefreshIndicator(
        onRefresh: _refresh,
        color: Colors.white,
        backgroundColor: AppGlassColors.baseDark,
        child: _content(c, analysis),
      );
    }

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Attack Statistics', style: TextStyle(color: Colors.white)),
        ),
        body: AppGradientBackground(child: SafeArea(child: body)),
      ),
    );
  }

  Widget _content(CaseModel c, AttackAnalysis analysis) {
    final isMigraine = c.diagnosisType == DiagnosisType.migraine;
    final periods = analysis.treatmentPeriods(_granularity);
    final treatmentStart = analysis.treatmentStartDay;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Full patient name here (wraps) — the AppBar title is one line only.
        Text(c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}', style: AppText.headline),
        const SizedBox(height: 16),
        // --- Baseline (before treatment) ---
        SectionHeader(
          icon: Icons.history_toggle_off,
          color: AppAccent.caseC,
          title: 'Baseline (before treatment)',
          subtitleText: treatmentStart == null
              ? 'No treatment session yet — every logged attack so far is baseline.'
              : 'Up to the first treatment session on ${_date(treatmentStart)}.',
        ),
        const SizedBox(height: 10),
        _BaselineCard(caseModel: c, logged: analysis.baseline(), isMigraine: isMigraine),
        const SizedBox(height: 24),

        // --- During treatment ---
        SectionHeader(
          icon: Icons.show_chart_outlined,
          color: AppAccent.patient,
          title: 'During treatment',
          subtitleText: treatmentStart == null
              ? 'Starts at the first treatment session.'
              : 'Since ${_date(treatmentStart)} (first treatment session).',
        ),
        const SizedBox(height: 10),
        if (treatmentStart == null)
          const GlassContainer(
            padding: EdgeInsets.all(14),
            child: Text('No treatment sessions recorded yet.', style: _Txt.hint),
          )
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<StatsGranularity>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: StatsGranularity.weekly, label: Text('Weekly')),
                ButtonSegment(value: StatsGranularity.monthly, label: Text('Monthly')),
                ButtonSegment(value: StatsGranularity.yearly, label: Text('Yearly')),
              ],
              selected: {_granularity},
              onSelectionChanged: (s) => setState(() => _granularity = s.first),
            ),
          ),
          const SizedBox(height: 10),
          GlassContainer(
            padding: const EdgeInsets.all(12),
            child: SessionsVsAttacksChart(
              periods: periods,
              granularity: _granularity,
              baseline: baselineForGranularity(c.monthlyEpisodeCount, _granularity),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'A period with no logged attacks counts as a clean zero only when the patient '
            'confirmed every past day of it ("no unlogged attacks").',
            style: _Txt.hint,
          ),
          const SizedBox(height: 10),
          for (final p in periods.reversed) ...[
            _PeriodCard(period: p, granularity: _granularity, isMigraine: isMigraine),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 16),

        // --- Full attack log ---
        SectionHeader(
          icon: Icons.list_alt_outlined,
          color: AppAccent.unlinked,
          title: 'Attack log',
          subtitleText: '${analysis.attacksNewestFirst.length} attacks logged in total',
        ),
        const SizedBox(height: 10),
        if (analysis.attacksNewestFirst.isEmpty)
          const GlassContainer(
            padding: EdgeInsets.all(14),
            child: Text('The patient has not logged any attacks yet.', style: _Txt.hint),
          )
        else
          AttackList(
            attacks: analysis.attacksNewestFirst,
            strings: AttackListStrings.en,
            initialLimit: 20,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label, style: _Txt.label)),
            Expanded(child: Text(value, style: _Txt.value)),
          ],
        ),
      );
}

/// The lines shared by baseline and period cards: duration range/average,
/// severity, medication use, late/approximate counts.
List<Widget> _attackDetailRows(PeriodStats p, bool isMigraine) {
  if (p.attackCount == 0) return const [];
  return [
    _Row('Average attack duration', formatAttackDuration(p.avgDurationSeconds!)),
    _Row(
      'Shortest – longest',
      '${formatAttackDuration(p.minDurationSeconds!)} – ${formatAttackDuration(p.maxDurationSeconds!)}',
    ),
    if (isMigraine && p.avgSeverity != null) _Row('Average severity', '${p.avgSeverity!.toStringAsFixed(1)} / 10'),
    _Row(
      'With medication',
      '${p.medicatedCount} of ${p.attackCount} (${(p.medicatedShare! * 100).round()}%)',
    ),
    if (p.lateCount > 0) _Row('Logged late', '${p.lateCount} (over 24 h after the attack)'),
    if (p.approximateCount > 0) _Row('Approximate time', '${p.approximateCount}'),
  ];
}

class _BaselineCard extends StatelessWidget {
  const _BaselineCard({required this.caseModel, required this.logged, required this.isMigraine});
  final CaseModel caseModel;
  final PeriodStats logged;
  final bool isMigraine;

  @override
  Widget build(BuildContext context) {
    final c = caseModel;
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Entered by the doctor', style: _Txt.title),
          const SizedBox(height: 6),
          _Row('Average attacks / month', c.monthlyEpisodeCount?.toString() ?? '—'),
          _Row(
            'Average attack duration',
            c.episodeDurationMinutes != null ? formatAttackDuration(c.episodeDurationMinutes! * 60) : '—',
          ),
          const SizedBox(height: 12),
          const Text('Logged by the patient before treatment', style: _Txt.title),
          const SizedBox(height: 6),
          _Row('Attacks', '${logged.attackCount}'),
          ..._attackDetailRows(logged, isMigraine),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.granularity, required this.isMigraine});
  final PeriodStats period;
  final StatsGranularity granularity;
  final bool isMigraine;

  static String _title(PeriodStats p, StatsGranularity g) => switch (g) {
        StatsGranularity.weekly =>
          'Week of ${_date(p.start)} – ${_date(p.end.subtract(const Duration(days: 1)))}',
        StatsGranularity.monthly => SessionsVsAttacksChart.periodLabel(p.start, g),
        StatsGranularity.yearly => '${p.start.year}',
      };

  @override
  Widget build(BuildContext context) {
    final p = period;
    final (statusLabel, statusColor) = switch (p.confirmation) {
      ConfirmationStatus.confirmed => ('Confirmed', AppAccent.patient),
      ConfirmationStatus.partial => ('Partly confirmed (${p.confirmedDays}/${p.pastDays} days)', AppAccent.caseC),
      ConfirmationStatus.unconfirmed => ('Unconfirmed', Colors.white54),
      ConfirmationStatus.inProgress => ('In progress', Colors.white54),
    };
    final attacksText = p.isUnconfirmedZero
        ? '0 attacks logged (unconfirmed)'
        : '${p.attackCount} ${p.attackCount == 1 ? 'attack' : 'attacks'}';

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_title(p, granularity), style: _Txt.title)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.7)),
                ),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Row('Attacks', attacksText),
          _Row('Sessions', '${p.sessions}'),
          ..._attackDetailRows(p, isMigraine),
        ],
      ),
    );
  }
}

/// Compact attack summary for the doctor's/engineer's case screen: attacks
/// this month vs last month, this month's average duration and severity
/// (migraine), and a button to the detailed statistics screen.
class AttackSummaryCard extends ConsumerWidget {
  const AttackSummaryCard({
    super.key,
    required this.caseModel,
    required this.sessionsProvider,
  });

  final CaseModel caseModel;
  final AutoDisposeFutureProvider<List<SessionModel>> sessionsProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = caseModel;
    final attacksAsync = ref.watch(caseAttacksProvider(c.id));
    Widget stats = attacksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (e, _) => Text('Failed to load attacks: $e', style: AppText.error),
      data: (attacks) {
        final analysis = AttackAnalysis(
          caseCreatedAt: c.createdAt,
          sessions: const [],
          attacks: attacks,
          confirmations: const <AttackLogConfirmationModel>[],
        );
        final thisMonth = analysis.calendarMonth(0);
        final lastMonth = analysis.calendarMonth(1);
        final diff = thisMonth.attackCount - lastMonth.attackCount;
        return Row(
          children: [
            Expanded(child: _Figure('This month', '${thisMonth.attackCount}')),
            Expanded(child: _Figure('Last month', '${lastMonth.attackCount}')),
            Expanded(
              child: _Figure(
                'Change',
                diff == 0 ? '±0' : (diff > 0 ? '+$diff' : '$diff'),
                color: diff > 0 ? AppAccent.unlinked : (diff < 0 ? AppAccent.patient : null),
              ),
            ),
          ],
        );
      },
    );

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stats,
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AttackStatisticsScreen(caseModel: c, sessionsProvider: sessionsProvider),
              ),
            ),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('View detailed statistics'),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color ?? Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(label, style: _Txt.hint, textAlign: TextAlign.center),
        ],
      );
}
