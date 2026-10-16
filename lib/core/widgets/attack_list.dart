import 'package:flutter/material.dart';

import '../attacks/attack_models.dart';
import '../attacks/attack_stats.dart';
import '../theme/app_theme.dart';
import '../time/baghdad_time.dart';
import 'glass_container.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// UI strings for [AttackList] (Arabic, for the patient). Direction
/// follows the ambient [Directionality].
class AttackListStrings {
  const AttackListStrings({
    required this.arabicDurations,
    required this.severity,
    required this.medication,
    required this.noMedication,
    required this.approximate,
    required this.lateLogged,
    required this.showAll,
    required this.showLess,
    required this.delete,
  });

  final bool arabicDurations;
  final String Function(int severity) severity;
  final String medication;
  final String noMedication;
  final String approximate;
  final String Function(Duration delay) lateLogged;
  final String Function(int total) showAll;
  final String showLess;
  final String delete;

  static final ar = AttackListStrings(
    arabicDurations: true,
    severity: (s) => 'الشدة $s/10',
    medication: 'أخذ دواء',
    noMedication: 'بدون دواء',
    approximate: 'تقريبي',
    lateLogged: (d) => 'سُجّلت بعد ${d.inDays >= 1 ? '${d.inDays} يوم' : '${d.inHours} ساعة'}',
    showAll: (n) => 'عرض كل النوبات ($n)',
    showLess: 'عرض أقل',
    delete: 'حذف',
  );
}

/// The attack log: newest first, one row per attack with date/time
/// (Baghdad), duration, severity (migraine), medication, and badges for
/// approximate time and late logging. Shown on the patient home screen.
class AttackList extends StatefulWidget {
  const AttackList({
    super.key,
    required this.attacks,
    required this.strings,
    this.initialLimit,
    this.canDelete,
    this.onDelete,
  });

  /// Newest first.
  final List<AttackEventModel> attacks;
  final AttackListStrings strings;

  /// Show only this many until "show all" is tapped; null = show all.
  final int? initialLimit;
  final bool Function(AttackEventModel attack)? canDelete;
  final void Function(AttackEventModel attack)? onDelete;

  @override
  State<AttackList> createState() => _AttackListState();
}

class _AttackListState extends State<AttackList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final limit = widget.initialLimit;
    final collapsible = limit != null && widget.attacks.length > limit;
    final visible =
        collapsible && !_expanded ? widget.attacks.take(limit).toList() : widget.attacks;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            _AttackTile(
              attack: visible[i],
              strings: s,
              onDelete: widget.onDelete != null && (widget.canDelete?.call(visible[i]) ?? true)
                  ? () => widget.onDelete!(visible[i])
                  : null,
            ),
            if (i != visible.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
          if (collapsible)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: Text(_expanded ? s.showLess : s.showAll(widget.attacks.length)),
            ),
        ],
      ),
    );
  }
}

class _AttackTile extends StatelessWidget {
  const _AttackTile({required this.attack, required this.strings, this.onDelete});
  final AttackEventModel attack;
  final AttackListStrings strings;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final t = toBaghdad(attack.occurredAt);
    final when = '${t.year}/${_two(t.month)}/${_two(t.day)}  '
        '${attack.timeIsApproximate ? '~' : ''}${_two(t.hour)}:${_two(t.minute)}';
    const hint = TextStyle(color: Colors.white60, fontSize: 12);

    final details = <String>[
      formatAttackDuration(attack.durationSeconds, arabic: s.arabicDurations),
      if (attack.severity != null) s.severity(attack.severity!),
      attack.tookMedication ? s.medication : s.noMedication,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(color: AppAccent.unlinked, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(when, style: AppText.tileTitle),
                const SizedBox(height: 2),
                Text(details.join(' · '), style: hint),
                if (attack.timeIsApproximate || attack.isLateLogged) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (attack.timeIsApproximate) _Badge(s.approximate, Colors.white54),
                      if (attack.isLateLogged)
                        _Badge(s.lateLogged(attack.createdAt.difference(attack.occurredAt)),
                            AppAccent.caseC),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: s.delete,
              icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}
