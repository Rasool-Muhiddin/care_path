import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_model.dart';
import '../patient_providers.dart';

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
    return AlertDialog(
      title: const Text('إنهاء الجلسة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            const Text('كيف كانت تجربتك بهذي الجلسة؟'),
            if (widget.durationMinutes != null) ...[
              const SizedBox(height: 4),
              Text(
                'مدة الجلسة: ${widget.durationMinutes} دقيقة',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: PatientFeeling.values.map((feeling) {
                final isSelected = _selectedFeeling == feeling;
                return ChoiceChip(
                  label: Text(feeling.label),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFeeling = feeling),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'ملاحظة (اختياري)',
                hintText: 'أي شي تحب تضيفه...',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}