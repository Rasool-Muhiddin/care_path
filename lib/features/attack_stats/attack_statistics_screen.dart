import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/attacks/attack_models.dart';
import '../../core/attacks/attack_repository.dart';
import '../../core/attacks/attack_stats.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/widgets/ltr_scope.dart';
import '../../core/widgets/sessions_vs_attacks_chart.dart';
import '../doctor/models/case_model.dart';
import '../patient/models/session_model.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}/${_two(d.month)}/${_two(d.day)}';

class _Txt {
  static const label = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const value = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
}

/// The period the statistics screen covers. Defaults to [last3Months] so a
/// case with years of data opens on recent, readable numbers.
enum StatsPeriod {
  last3Months('Last 3 months'),
  thisYear('This year'),
  allTime('All time'),
  custom('Custom');

  const StatsPeriod(this.label);
  final String label;
}

/// Detailed attack statistics for one case — shared by the doctor and the
/// engineer (English, LTR; the patient doesn't get this screen).
///
/// Top to bottom: period selector, summary cards for that period, and the
/// sessions-vs-attacks chart grouped weekly/monthly/yearly. Nothing here
/// grows with the size of the history: the chart is capped at
/// [maxChartPeriods] bars and there are no per-attack or per-period lists.
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
  StatsPeriod _period = StatsPeriod.last3Months;

  /// Baghdad days [start, end) of a custom range; null until one is picked.
  (DateTime, DateTime)? _customRange;

  /// Null = follow [autoGranularity] for the current range.
  StatsGranularity? _granularity;

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

  /// Baghdad days [start, end) of the selected period, never starting
  /// before the case (= treatment) start.
  (DateTime, DateTime) _rangeFor(AttackAnalysis a) {
    final today = a.today;
    final end = today.add(const Duration(days: 1));
    final (start, rangeEnd) = switch (_period) {
      StatsPeriod.last3Months => (_monthsBefore(today, 3), end),
      StatsPeriod.thisYear => (DateTime.utc(today.year), end),
      StatsPeriod.allTime => (a.treatmentStartDay, end),
      StatsPeriod.custom => _customRange ?? (_monthsBefore(today, 3), end),
    };
    final from = start.isBefore(a.treatmentStartDay) ? a.treatmentStartDay : start;
    return (from.isBefore(rangeEnd) ? from : today, rangeEnd);
  }

  /// Same day [months] calendar months earlier, clamped to that month's
  /// last day (May 31 -> Feb 28).
  static DateTime _monthsBefore(DateTime day, int months) {
    final firstOfMonth = DateTime.utc(day.year, day.month - months);
    final lastDay = DateTime.utc(firstOfMonth.year, firstOfMonth.month + 1, 0).day;
    return DateTime.utc(firstOfMonth.year, firstOfMonth.month, day.day > lastDay ? lastDay : day.day);
  }

  Future<void> _selectPeriod(StatsPeriod period, AttackAnalysis a) async {
    if (period != StatsPeriod.custom) {
      setState(() {
        _period = period;
        _granularity = null;
      });
      return;
    }
    // The picker works on local date-only values; Baghdad days are UTC dates.
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final (start, end) = _rangeFor(a);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: local(a.treatmentStartDay),
      lastDate: local(a.today),
      initialDateRange: DateTimeRange(
        start: local(start),
        end: local(end.subtract(const Duration(days: 1))),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = StatsPeriod.custom;
      _customRange = (
        DateTime.utc(picked.start.year, picked.start.month, picked.start.day),
        DateTime.utc(picked.end.year, picked.end.month, picked.end.day + 1),
      );
      _granularity = null;
    });
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
    final (start, end) = _rangeFor(analysis);
    final summary = analysis.summarize(start, end);

    // Only offer groupings that keep the chart readable for this range.
    bool allowed(StatsGranularity g) =>
        g == StatsGranularity.yearly || periodCountIn(start, end, g) <= maxChartPeriods;
    final requested = _granularity ?? autoGranularity(start, end);
    final granularity = allowed(requested) ? requested : StatsGranularity.yearly;
    final periods = analysis.periods(start, end, granularity);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Full patient name here (wraps) — the AppBar title is one line only.
        Text(c.patientName.isNotEmpty ? c.patientName : 'Patient #${c.patientId}', style: AppText.headline),
        const SizedBox(height: 12),

        // --- Period selector ---
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in StatsPeriod.values)
              ChoiceChip(
                label: Text(p.label),
                selected: _period == p,
                showCheckmark: false,
                labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                selectedColor: Colors.white.withValues(alpha: 0.22),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                avatar: p == StatsPeriod.custom
                    ? const Icon(Icons.date_range_outlined, size: 16, color: Colors.white)
                    : null,
                onSelected: (_) => _selectPeriod(p, analysis),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${_date(start)} – ${_date(end.subtract(const Duration(days: 1)))}  ·  '
          'Treatment started ${_date(analysis.treatmentStartDay)}',
          style: _Txt.hint,
        ),
        const SizedBox(height: 16),

        // --- Summary for the selected period ---
        _SummaryGrid(summary: summary, isMigraine: isMigraine),
        if (summary.pastDays > 0) ...[
          const SizedBox(height: 8),
          Text(
            'The patient confirmed "no unlogged attacks" for ${summary.confirmedDays} of '
            '${summary.pastDays} past days in this period.',
            style: _Txt.hint,
          ),
        ],
        const SizedBox(height: 24),

        // --- Sessions vs attacks chart ---
        const SectionHeader(
          icon: Icons.bar_chart_outlined,
          color: AppAccent.patient,
          title: 'Sessions vs attacks',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<StatsGranularity>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: StatsGranularity.weekly,
                label: const Text('Weekly'),
                enabled: allowed(StatsGranularity.weekly),
              ),
              ButtonSegment(
                value: StatsGranularity.monthly,
                label: const Text('Monthly'),
                enabled: allowed(StatsGranularity.monthly),
              ),
              const ButtonSegment(value: StatsGranularity.yearly, label: Text('Yearly')),
            ],
            selected: {granularity},
            onSelectionChanged: (s) => setState(() => _granularity = s.first),
          ),
        ),
        const SizedBox(height: 10),
        GlassContainer(
          padding: const EdgeInsets.all(12),
          child: SessionsVsAttacksChart(periods: periods, granularity: granularity),
        ),
      ],
    );
  }
}

/// Compact figures for the selected period, two per row.
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.isMigraine});
  final PeriodStats summary;
  final bool isMigraine;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final hasAttacks = s.attackCount > 0;
    final tiles = [
      _SummaryTile(icon: Icons.bolt_outlined, color: AppAccent.unlinked, label: 'Attacks', value: '${s.attackCount}'),
      _SummaryTile(
        icon: Icons.event_note_outlined,
        color: AppAccent.patient,
        label: 'Sessions',
        value: '${s.sessions}',
      ),
      _SummaryTile(
        icon: Icons.timer_outlined,
        color: AppAccent.doctor,
        label: 'Average duration',
        value: hasAttacks ? formatAttackDuration(s.avgDurationSeconds!) : '—',
        detail: hasAttacks
            ? 'Range ${formatAttackDuration(s.minDurationSeconds!)} – ${formatAttackDuration(s.maxDurationSeconds!)}'
            : null,
      ),
      if (isMigraine)
        _SummaryTile(
          icon: Icons.speed_outlined,
          color: AppAccent.caseC,
          label: 'Average severity',
          value: s.avgSeverity != null ? '${s.avgSeverity!.toStringAsFixed(1)} / 10' : '—',
        ),
      _SummaryTile(
        icon: Icons.medication_outlined,
        color: AppAccent.device,
        label: 'With medication',
        value: hasAttacks ? '${(s.medicatedShare! * 100).round()}%' : '—',
        detail: hasAttacks ? '${s.medicatedCount} of ${s.attackCount} attacks' : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.detail,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: _Txt.label)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: _Txt.value),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail!, style: _Txt.hint),
          ],
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
