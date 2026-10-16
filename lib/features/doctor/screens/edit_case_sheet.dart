import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';

/// Opens the "Edit Case" form (status, total sessions planned, initial
/// evaluation, treatment plan) in a modal bottom sheet. Resolves to the
/// updated case after a successful save, or null if the doctor closed it.
Future<CaseModel?> showEditCaseSheet(BuildContext context, CaseModel caseModel) {
  return showModalBottomSheet<CaseModel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppGlassColors.baseDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => LtrScope(child: _EditCaseForm(caseModel: caseModel)),
  );
}

/// Shared text styles for the sheet (white-on-navy).
class _Txt {
  static const title = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);
  static const fieldLabel = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
  static const body = TextStyle(color: Colors.white, fontSize: 14);
}

/// A field label with a small colored leading icon, used above every
/// editable field instead of a plain white caption.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.icon});
  final String text;
  final IconData? icon;
  static const Color color = AppAccent.doctor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(text, style: _Txt.fieldLabel)),
      ],
    );
  }
}

/// Reusable "field wrapped in a glass panel" [InputDecoration], used for
/// every [TextFormField]/[DropdownButtonFormField] in the sheet.
InputDecoration _fieldDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: _Txt.hint,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );
}

class _EditCaseForm extends ConsumerStatefulWidget {
  const _EditCaseForm({required this.caseModel});
  final CaseModel caseModel;

  @override
  ConsumerState<_EditCaseForm> createState() => _EditCaseFormState();
}

class _EditCaseFormState extends ConsumerState<_EditCaseForm> {
  late CaseStatus _status;
  late final TextEditingController _treatmentPlanController;
  late final TextEditingController _initialEvaluationController;
  late final TextEditingController _totalSessionsController;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.caseModel.status;
    _treatmentPlanController = TextEditingController(text: widget.caseModel.treatmentPlan);
    _initialEvaluationController = TextEditingController(text: widget.caseModel.initialEvaluation);
    _totalSessionsController =
        TextEditingController(text: widget.caseModel.totalSessionsPlanned?.toString() ?? '');
    _treatmentPlanController.addListener(_markChanged);
    _initialEvaluationController.addListener(_markChanged);
    _totalSessionsController.addListener(_markChanged);
  }

  void _markChanged() {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  @override
  void dispose() {
    _treatmentPlanController.dispose();
    _initialEvaluationController.dispose();
    _totalSessionsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(doctorRepositoryProvider).updateCase(
            widget.caseModel.id,
            CaseUpdatePayload(
              status: _status,
              treatmentPlan: _treatmentPlanController.text.trim(),
              initialEvaluation: _initialEvaluationController.text.trim(),
              totalSessionsPlanned: int.tryParse(_totalSessionsController.text.trim()),
            ),
          );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keep the focused field above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_outlined, size: 18, color: AppAccent.doctor),
                const SizedBox(width: 8),
                const Expanded(child: Text('Edit Case', style: _Txt.title)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: 'Close',
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _FieldLabel('Status', icon: Icons.flag_outlined),
            const SizedBox(height: 8),
            DropdownButtonFormField<CaseStatus>(
              // isExpanded: يأخذ عرض الحقل، والنص الطويل يلتف بدل أن يتجاوز الشاشة
              isExpanded: true,
              initialValue: _status,
              decoration: _fieldDecoration(),
              dropdownColor: AppGlassColors.baseDark,
              style: _Txt.body,
              iconEnabledColor: Colors.white70,
              items: CaseStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
              onChanged: (value) {
                setState(() {
                  _status = value!;
                  _hasUnsavedChanges = true;
                });
              },
            ),
            const SizedBox(height: 20),

            const _FieldLabel('Total Sessions Planned', icon: Icons.format_list_numbered),
            const SizedBox(height: 8),
            TextFormField(
              controller: _totalSessionsController,
              keyboardType: TextInputType.number,
              style: _Txt.body,
              cursorColor: Colors.white,
              decoration: _fieldDecoration(hint: 'e.g. 20'),
            ),
            const SizedBox(height: 20),

            const _FieldLabel('Initial Evaluation', icon: Icons.fact_check_outlined),
            const SizedBox(height: 8),
            TextFormField(
              controller: _initialEvaluationController,
              maxLines: 3,
              style: _Txt.body,
              cursorColor: Colors.white,
              decoration: _fieldDecoration(),
            ),
            const SizedBox(height: 20),

            const _FieldLabel('Treatment Plan', icon: Icons.assignment_outlined),
            const SizedBox(height: 8),
            TextFormField(
              controller: _treatmentPlanController,
              maxLines: 3,
              style: _Txt.body,
              cursorColor: Colors.white,
              decoration: _fieldDecoration(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppText.error),
            ],
            const SizedBox(height: 20),

            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
                onPressed: (_isSaving || !_hasUnsavedChanges) ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
