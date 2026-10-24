import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../attacks/attack_stats.dart';

/// Grouped bar chart comparing sessions done vs attacks logged per period
/// (weekly / monthly / yearly — chosen by the parent, which caps the
/// number of periods at [maxChartPeriods]). Attack counts come from the
/// patient's individual attack records (AttackEvent).
///
/// [baselinePerMonth] (Case.monthly_episode_count — attacks per month before
/// treatment, entered by the doctor) is drawn as a dashed yellow line,
/// converted to the chart's period length; hidden when unknown or 0.
class SessionsVsAttacksChart extends StatelessWidget {
  const SessionsVsAttacksChart({
    super.key,
    required this.periods,
    required this.granularity,
    this.baselinePerMonth,
  });

  /// Oldest first.
  final List<PeriodStats> periods;
  final StatsGranularity granularity;
  final int? baselinePerMonth;

  /// لون بار الجلسات (رصاصي فاتح مائل للأبيض) — يُستخدم بالبار والـ legend
  static const Color _sessionsColor = Color(0xFFD9DCE1);

  /// خط الـ baseline (عدد النوبات قبل العلاج)
  static const Color baselineColor = Color(0xFFFACC15);

  /// The before-treatment monthly rate expressed per [g] period
  /// (weekly = monthly × 12 / 52, yearly = monthly × 12). Null = no line.
  static double? baselineFor(int? perMonth, StatsGranularity g) {
    if (perMonth == null || perMonth <= 0) return null;
    return switch (g) {
      StatsGranularity.weekly => perMonth * 12 / 52,
      StatsGranularity.monthly => perMonth.toDouble(),
      StatsGranularity.yearly => perMonth * 12.0,
    };
  }

  static String _formatRate(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(v < 10 ? 2 : 1);

  static const _periodUnit = {
    StatsGranularity.weekly: 'week',
    StatsGranularity.monthly: 'month',
    StatsGranularity.yearly: 'year',
  };

  /// عرض كل مجموعة أعمدة (جلسات + نوبات) — إذا عدد المجموعات كبير
  /// (مثلاً 5 شهور بالأسبوعي) الشارت يصير قابل للتمرير أفقياً.
  static const double _groupWidth = 44;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// X-axis label of period [i]: the period on the first line and, for
  /// weekly/monthly, the year on a second line — only on the first label and
  /// where the year changes ("Mar" over "2026", then "Apr", "May", …).
  /// Keeps every label within one [_groupWidth] column so none overlap.
  static String periodLabel(List<PeriodStats> periods, int i, StatsGranularity g) {
    final start = periods[i].start;
    final newYear = i == 0 || periods[i - 1].start.year != start.year;
    final year = newYear ? '\n${start.year}' : '';
    return switch (g) {
      StatsGranularity.weekly => '${_two(start.month)}/${_two(start.day)}$year',
      StatsGranularity.monthly => '${_months[start.month - 1]}$year',
      StatsGranularity.yearly => '${start.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final attackColor = Theme.of(context).colorScheme.error;
    final baseline = baselineFor(baselinePerMonth, granularity);

    // maxY رقم صحيح دائماً (حتى ما يطلع 8.2 ويتداخل مع أرقام المحور)،
    // ويشمل الـ baseline حتى لا يُقص خطه
    var highest = baseline ?? 0.0;
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
            if (baseline != null)
              _LegendDash(
                color: baselineColor,
                label: 'Baseline (before treatment): '
                    '${_formatRate(baseline)} / ${_periodUnit[granularity]}',
              ),
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
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          if (baseline != null)
                            HorizontalLine(
                              y: baseline,
                              color: baselineColor,
                              strokeWidth: 2,
                              dashArray: const [6, 4],
                            ),
                        ],
                      ),
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            // أعداد صحيحة فقط (بمحور صغير قد تأتي قيم 0.5 فيتكرر "0")
                            getTitlesWidget: (value, meta) => value != value.roundToDouble()
                                ? const SizedBox.shrink()
                                : Text(
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
                            // سطران: الفترة ثم السنة تحتها
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= periods.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  periodLabel(periods, i, granularity),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  softWrap: false,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.25),
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

/// Legend entry for the dashed baseline line.
class _LegendDash extends StatelessWidget {
  const _LegendDash({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    Widget dash() => Container(width: 6, height: 2, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dash(),
        const SizedBox(width: 3),
        dash(),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
      ],
    );
  }
}
