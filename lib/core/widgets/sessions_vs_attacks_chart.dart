import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../features/doctor/models/weekly_episode_log_model.dart';
import '../../features/patient/models/session_model.dart';

enum _ChartGranularity { weekly, monthly }

/// Grouped bar chart comparing sessions done vs attacks reported, either
/// per week (each bar = one WeeklyEpisodeLog) or per calendar month
/// (4 weeks combined, as suggested) — toggled via the segmented control.
/// Attack counts come from WeeklyEpisodeLog (patient's mandatory weekly
/// reports), not from the old static Case.monthly_episode_count, since
/// only the weekly reports form an actual time series.
class SessionsVsAttacksChart extends StatefulWidget {
  const SessionsVsAttacksChart({super.key, required this.sessions, required this.episodeLogs});
  final List<SessionModel> sessions;
  final List<WeeklyEpisodeLogModel> episodeLogs;

  @override
  State<SessionsVsAttacksChart> createState() => _SessionsVsAttacksChartState();
}

class _SessionsVsAttacksChartState extends State<SessionsVsAttacksChart> {
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