import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../models/session_model.dart';
import '../patient_providers.dart';

/// Category accent colors — every screen picks its palette from here so
/// data reads by color instead of a flat, uniform white.
class _Accent {
  static const Color doctor = Color(0xFF5AC8FA);
  static const Color patient = Color(0xFF34D399);
  static const Color caseC = Color(0xFFFBBF24);
  static const Color device = Color(0xFFA78BFA);
  static const Color unlinked = Color(0xFFF87171);
  static const Color clinic = Color(0xFF22D3EE);
}

/// Fixed text styles so every screen stays visually consistent.
class _Txt {
  static const headline = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700);
  static const sectionSubtitle = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const tileTitle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white60, fontSize: 12);
  static const body = TextStyle(color: Colors.white60, fontSize: 13);
  static const error = TextStyle(color: Color(0xFFF87171));
}

/// Small circular badge behind a data-category icon: tinted fill,
/// tinted border, colored icon — replaces flat white avatars/icons.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Unified section header: colored side bar + small icon + white title
/// + a lighter subtitle line (which may contain a glowing highlight,
/// e.g. a count).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.subtitleSpans,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<InlineSpan>? subtitleSpans;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: subtitleSpans != null ? 34 : 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Txt.sectionTitle),
              if (subtitleSpans != null) ...[
                const SizedBox(height: 2),
                Text.rich(TextSpan(style: _Txt.sectionSubtitle, children: subtitleSpans)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// نافذة "إنهاء الجلسة" — اختيار سريع لرد الفعل + ملاحظة اختيارية.
/// [durationMinutes]: المدة المحسوبة تلقائياً من عداد "بدء الجلسة" بالشاشة
/// الرئيسية (null لو المريض ضغط "إنهاء الجلسة" مباشرة بدون بدء عداد).
Future<bool?> showEndSessionDialog(
  BuildContext context,
  int caseId, {
  int? durationMinutes,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _EndSessionDialog(caseId: caseId, durationMinutes: durationMinutes),
  );
}

class _EndSessionDialog extends ConsumerStatefulWidget {
  const _EndSessionDialog({required this.caseId, this.durationMinutes});
  final int caseId;
  final int? durationMinutes;

  @override
  ConsumerState<_EndSessionDialog> createState() => _EndSessionDialogState();
}

class _EndSessionDialogState extends ConsumerState<_EndSessionDialog> {
  PatientFeeling? _selectedFeeling;
  final _noteController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedFeeling == null) {
      setState(() => _errorMessage = 'اختر تقييمك للجلسة أولاً');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(patientRepositoryProvider).createSession(
            NewSessionPayload(
              caseId: widget.caseId,
              feeling: _selectedFeeling!,
              note: _noteController.text,
              durationMinutes: widget.durationMinutes,
            ),
          );
      ref.invalidate(mySessionsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: 'إنهاء الجلسة',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Row(
                children: [
                  _IconBadge(icon: Icons.error_outline, color: _Accent.unlinked, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_errorMessage!, style: _Txt.error),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _SectionHeader(
              icon: Icons.mood_outlined,
              color: _Accent.patient,
              title: 'كيف كانت تجربتك بهذي الجلسة؟',
              subtitleSpans: widget.durationMinutes != null
                  ? [
                      const TextSpan(text: 'مدة الجلسة: '),
                      TextSpan(
                        text: '${widget.durationMinutes}',
                        style: TextStyle(
                          color: _Accent.patient,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(color: _Accent.patient.withValues(alpha: 0.55), blurRadius: 14),
                          ],
                        ),
                      ),
                      const TextSpan(text: ' دقيقة'),
                    ]
                  : null,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PatientFeeling.values.map((feeling) {
                final isSelected = _selectedFeeling == feeling;
                return ChoiceChip(
                  label: Text(feeling.label),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFeeling = feeling),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: isSelected ? AppGlassColors.baseDark : Colors.black,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  backgroundColor: _Accent.patient.withValues(alpha: 0.1),
                  selectedColor: _Accent.patient,
                  side: BorderSide(color: _Accent.patient.withValues(alpha: isSelected ? 0.7 : 0.3)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: glassInputDecoration(
                'ملاحظة (اختياري)',
              ).copyWith(hintText: 'أي شي تحب تضيفه...'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
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
}