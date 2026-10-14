import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/attacks/attack_models.dart';
import '../../../core/attacks/attack_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/baghdad_time.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/glass_container.dart';
import '../../doctor/models/case_model.dart' show CaseModel, DiagnosisType;

/// أقدم يوم يمكن تسجيل نوبة فيه = اليوم - 7 (نفس حد السيرفر ATTACK_MAX_DAYS_BACK)
const int _maxDaysBack = 7;

/// جزء تقريبي من اليوم لمن لا يتذكر الوقت بالضبط. يُخزَّن وقت ممثِّل
/// (منتصف الجزء تقريباً) مع time_is_approximate=true.
enum _DayPart {
  morning('صباحاً', 5, 9),
  noon('ظهراً', 12, 13),
  evening('مساءً', 16, 18),
  night('ليلاً', 21, 22);

  const _DayPart(this.label, this.startHour, this.representativeHour);
  final String label;
  final int startHour;
  final int representativeHour;
}

const _weekdayNames = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// يفتح نافذة "تسجيل نوبة" — بعد كل حفظ يمكن للمريض "تسجيل نوبة أخرى"
/// (لتسجيل عدة نوبات فائتة متتالية) أو الإنهاء. يرجّع عدد النوبات المسجّلة.
Future<int> showLogAttackDialog(BuildContext context, CaseModel myCase) async {
  final logged = await showDialog<int>(
    context: context,
    // الإغلاق دائماً عبر الأزرار حتى يرجع عدد ما سُجّل فعلاً
    barrierDismissible: false,
    builder: (_) => _LogAttackDialog(myCase: myCase),
  );
  return logged ?? 0;
}

class _LogAttackDialog extends ConsumerStatefulWidget {
  const _LogAttackDialog({required this.myCase});
  final CaseModel myCase;

  @override
  ConsumerState<_LogAttackDialog> createState() => _LogAttackDialogState();
}

class _LogAttackDialogState extends ConsumerState<_LogAttackDialog> {
  final _bigUnit = TextEditingController(); // ساعات (شقيقة) أو دقائق (صرع)
  final _smallUnit = TextEditingController(); // دقائق (شقيقة) أو ثوانٍ (صرع)
  late DateTime _day;
  bool _exactTime = true;
  TimeOfDay? _time;
  _DayPart? _part;
  int? _severity;
  bool? _tookMedication;
  bool _isSaving = false;
  String? _error;
  int _loggedCount = 0;
  bool _justSaved = false;

  bool get _isMigraine => widget.myCase.diagnosisType == DiagnosisType.migraine;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _day = baghdadToday();
    _exactTime = true;
    _time = null;
    _part = null;
    _severity = null;
    _tookMedication = null;
    _bigUnit.clear();
    _smallUnit.clear();
    _error = null;
  }

  @override
  void dispose() {
    _bigUnit.dispose();
    _smallUnit.dispose();
    super.dispose();
  }

  bool get _isToday => _day == baghdadToday();

  /// جزء اليوم متاح لليوم الحالي فقط إذا بدأ فعلاً.
  bool _partAvailable(_DayPart part) =>
      !_isToday || toBaghdad(DateTime.now()).hour >= part.startHour;

  String _dayLabel(DateTime day) {
    final diff = baghdadToday().difference(day).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${_weekdayNames[day.weekday - 1]} ${day.day}/${day.month}';
  }

  int? get _durationSeconds {
    final big = int.tryParse(_bigUnit.text.trim()) ?? 0;
    final small = int.tryParse(_smallUnit.text.trim()) ?? 0;
    final seconds = _isMigraine ? big * 3600 + small * 60 : big * 60 + small;
    return seconds > 0 ? seconds : null;
  }

  /// الوقت الحقيقي للنوبة من اختيار المريض (بتوقيت بغداد).
  DateTime? get _occurredAt {
    if (_exactTime) {
      final t = _time;
      if (t == null) return null;
      return fromBaghdadWallTime(_day.year, _day.month, _day.day, t.hour, t.minute);
    }
    final p = _part;
    if (p == null) return null;
    final representative = fromBaghdadWallTime(_day.year, _day.month, _day.day, p.representativeHour);
    final now = DateTime.now();
    // اليوم: الجزء الحالي لم ينتهِ بعد — لا نسجّل وقتاً في المستقبل
    return representative.isAfter(now) ? now : representative;
  }

  String? _validate() {
    final occurredAt = _occurredAt;
    if (occurredAt == null) return _exactTime ? 'اختر وقت بداية النوبة' : 'اختر جزء اليوم';
    if (occurredAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return 'لا يمكن اختيار وقت في المستقبل';
    }
    final seconds = _durationSeconds;
    if (seconds == null) return 'أدخل مدة النوبة';
    final maxSeconds = _isMigraine ? 72 * 3600 : 60 * 60;
    if (seconds > maxSeconds) {
      return _isMigraine ? 'أقصى مدة 72 ساعة' : 'أقصى مدة 60 دقيقة';
    }
    if (_isMigraine && _severity == null) return 'اختر شدة النوبة';
    if (_tookMedication == null) return 'أجب: هل أخذت دواء للنوبة؟';
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(attackRepositoryProvider).logAttack(
            NewAttackEventPayload(
              caseId: widget.myCase.id,
              occurredAt: _occurredAt!,
              timeIsApproximate: !_exactTime,
              durationSeconds: _durationSeconds!,
              severity: _isMigraine ? _severity : null,
              tookMedication: _tookMedication!,
            ),
          );
      ref.invalidate(caseAttacksProvider(widget.myCase.id));
      setState(() {
        _loggedCount++;
        _justSaved = true;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.fromDateTime(toBaghdad(DateTime.now())),
    );
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    // زر الرجوع يغلق مع إرجاع عدد النوبات المحفوظة (بدل null)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isSaving) Navigator.of(context).pop(_loggedCount);
      },
      child: _justSaved ? _savedView() : _formView(),
    );
  }

  Widget _formView() {
    return GlassDialog(
      title: 'تسجيل نوبة',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: AppText.error),
              const SizedBox(height: 10),
            ],
            const _Question('متى بدأت النوبة؟'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i <= _maxDaysBack; i++)
                  _choice(
                    _dayLabel(baghdadToday().subtract(Duration(days: i))),
                    _day == baghdadToday().subtract(Duration(days: i)),
                    () => setState(() {
                      _day = baghdadToday().subtract(Duration(days: i));
                      if (_part != null && !_partAvailable(_part!)) _part = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                _choice('وقت محدد', _exactTime, () => setState(() => _exactTime = true)),
                _choice('وقت تقريبي', !_exactTime, () => setState(() => _exactTime = false)),
              ],
            ),
            const SizedBox(height: 8),
            if (_exactTime)
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_time == null ? 'اختر الوقت' : _time!.format(context)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
              )
            else ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final part in _DayPart.values)
                    _choice(
                      part.label,
                      _part == part,
                      _partAvailable(part) ? () => setState(() => _part = part) : null,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('بعد منتصف الليل؟ اختر "وقت محدد".', style: AppText.tileSubtitle),
            ],
            const SizedBox(height: 16),
            const _Question('كم استمرت النوبة؟'),
            Row(
              children: [
                Expanded(child: _numberField(_bigUnit, _isMigraine ? 'ساعات' : 'دقائق')),
                const SizedBox(width: 10),
                Expanded(child: _numberField(_smallUnit, _isMigraine ? 'دقائق' : 'ثوانٍ')),
              ],
            ),
            if (_isMigraine) ...[
              const SizedBox(height: 16),
              const _Question('ما شدة النوبة؟ (1 خفيفة – 10 شديدة جداً)'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var s = 1; s <= 10; s++)
                    _choice('$s', _severity == s, () => setState(() => _severity = s)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const _Question('هل أخذت دواء للنوبة؟'),
            Wrap(
              spacing: 6,
              children: [
                _choice('نعم', _tookMedication == true, () => setState(() => _tookMedication = true)),
                _choice('لا', _tookMedication == false, () => setState(() => _tookMedication = false)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(_loggedCount),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 8),
        _primaryButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }

  Widget _savedView() {
    return GlassDialog(
      title: 'تم تسجيل النوبة',
      content: Row(
        children: [
          const IconBadge(icon: Icons.check_circle_outline, color: AppAccent.patient, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _loggedCount == 1 ? 'تم حفظ النوبة.' : 'تم حفظ $_loggedCount نوبات.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _reset();
            _justSaved = false;
          }),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('تسجيل نوبة أخرى'),
        ),
        const SizedBox(width: 8),
        _primaryButton(
          onPressed: () => Navigator.of(context).pop(_loggedCount),
          child: const Text('تم'),
        ),
      ],
    );
  }

  Widget _primaryButton({required VoidCallback? onPressed, required Widget child}) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
      onPressed: onPressed,
      child: child,
    );
  }

  Widget _choice(String label, bool selected, VoidCallback? onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? AppGlassColors.baseDark : (onTap == null ? Colors.black38 : Colors.black),
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: AppAccent.patient.withValues(alpha: 0.1),
      selectedColor: AppAccent.patient,
      side: BorderSide(color: AppAccent.patient.withValues(alpha: selected ? 0.7 : 0.3)),
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      decoration: glassInputDecoration(label),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AppText.tileTitle),
      );
}
