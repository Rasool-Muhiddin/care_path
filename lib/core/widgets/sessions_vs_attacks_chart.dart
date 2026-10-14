import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../attacks/attack_stats.dart';

/// Grouped bar chart comparing sessions done vs attacks logged per period
/// (weekly / monthly / yearly — chosen by the parent so the stats table
/// next to it follows the same periods). Attack counts come from the
/// patient's individual attack records (AttackEvent). An optional dashed
/// line marks the doctor's before-treatment baseline, scaled to the
/// period length (see baselineForGranularity).
class SessionsVsAttacksChart extends StatelessWidget {
  const SessionsVsAttacksChart({
    super.key,
    required this.periods,
    required this.granularity,
    this.baseline,
  });

  /// Oldest first.
  final List<PeriodStats> periods;
  final StatsGranularity granularity;
  final double? baseline;

  /// لون بار الجلسات (رصاصي فاتح مائل للأبيض) — يُستخدم بالبار والـ legend
  static const Color _sessionsColor = Color(0xFFD9DCE1);
  static const Color _baselineColor = Color(0xFFFBBF24);

  /// عرض كل مجموعة أعمدة (جلسات + نوبات) — إذا عدد المجموعات كبير
  /// (مثلاً 5 شهور بالأسبوعي) الشارت يصير قابل للتمرير أفقياً.
  static const double _groupWidth = 44;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String periodLabel(DateTime start, StatsGranularity g) => switch (g) {
        StatsGranularity.weekly => '${_two(start.month)}/${_two(start.day)}',
        StatsGranularity.monthly => '${start.year}-${_two(start.month)}',
        StatsGranularity.yearly => '${start.year}',
      };

  @override
  Widget build(BuildContext context) {
    final attackColor = Theme.of(context).colorScheme.error;

    // maxY رقم صحيح دائماً (حتى ما يطلع 8.2 ويتداخل مع أرقام المحور)
    var highest = baseline ?? 0;
    for (final p in periods) {
      if (p.sessions > highest) highest = p.sessions.toDouble();
      if (p.attackCount > highest) highest = p.attackCount.toDouble();
    }
    final maxY = periods.isEmpty ? 10.0 : (highest * 1.2).ceilToDouble() + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            const _LegendDot(color: _sessionsColor, label: 'Sessions'),
            _LegendDot(color: attackColor, label: 'Attacks'),
            if (baseline != null) const _LegendDot(color: _baselineColor, label: 'Baseline (before treatment)'),
          ],
        ),
        const SizedBox(height: 12),
        if (periods.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Not enough data yet for this view.',
              style: TextStyle(color: Colors.white),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final neededWidth = periods.length * _groupWidth;
              final chartWidth =
                  neededWidth > constraints.maxWidth ? neededWidth : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // أحدث فترة ظاهرة أولاً
                reverse: true,
                child: SizedBox(
                  width: chartWidth,
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          if (baseline != null)
                            HorizontalLine(
                              y: baseline!,
                              color: _baselineColor,
                              strokeWidth: 1.5,
                              dashArray: [6, 4],
                            ),
                        ],
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= periods.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  periodLabel(periods[i].start, granularity),
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < periods.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: periods[i].sessions.toDouble(),
                                color: _sessionsColor,
                                width: 10,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              BarChartRodData(
                                toY: periods[i].attackCount.toDouble(),
                                color: attackColor,
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
              );
            },
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
        Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
      ],
    );
  }
}
