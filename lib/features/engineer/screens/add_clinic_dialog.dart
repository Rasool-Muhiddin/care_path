import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import '../models/engineer_model.dart';

/// Dialog to add a new clinic: name, address, phone, contact person,
/// and the responsible engineer (picked from the team list).
Future<bool?> showAddClinicDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => const _AddClinicDialog(),
  );
}

/// Dialog to edit an existing clinic — same form, pre-filled and
/// submitting a PATCH instead of a POST.
Future<bool?> showEditClinicDialog(BuildContext context, ClinicModel clinic) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _AddClinicDialog(clinic: clinic),
  );
}

class _AddClinicDialog extends ConsumerStatefulWidget {
  const _AddClinicDialog({this.clinic});

  /// When non-null, the dialog opens pre-filled in edit mode.
  final ClinicModel? clinic;

  bool get isEditing => clinic != null;

  @override
  ConsumerState<_AddClinicDialog> createState() => _AddClinicDialogState();
}

class _AddClinicDialogState extends ConsumerState<_AddClinicDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.clinic?.name ?? '');
  late final _addressController = TextEditingController(text: widget.clinic?.address ?? '');
  late final _phoneController = TextEditingController(text: widget.clinic?.phoneNumber ?? '');
  late final _contactPersonController =
      TextEditingController(text: widget.clinic?.contactPerson ?? '');

  EngineerModel? _selectedEngineer;
  // يُحدَّد المهندس الحالي مرة واحدة فقط (وضع التعديل) حتى يبقى "None" مختاراً
  bool _engineerResolved = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _contactPersonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final payload = ClinicPayload(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        contactPerson: _contactPersonController.text.trim(),
        responsibleEngineerId: _selectedEngineer?.id,
      );
      final repo = ref.read(engineerRepositoryProvider);
      if (widget.isEditing) {
        await repo.updateClinic(widget.clinic!.id, payload);
      } else {
        await repo.createClinic(payload);
      }
      ref.invalidate(clinicsListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engineersAsync = ref.watch(engineersListProvider);

    return LtrScope(
      child: GlassDialog(
        title: widget.isEditing ? 'Edit Clinic' : 'New Clinic',
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Row(
                    children: [
                      IconBadge(icon: Icons.error_outline, color: AppAccent.unlinked, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_errorMessage!, style: AppText.error),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: glassInputDecoration('Clinic Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: glassInputDecoration('Address'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: glassInputDecoration('Phone Number'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contactPersonController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: glassInputDecoration('Contact Person'),
                ),
                const SizedBox(height: 16),
                SectionHeader(
                  icon: Icons.engineering_outlined,
                  color: AppAccent.clinic,
                  title: 'Supervising Engineer',
                ),
                const SizedBox(height: 8),
                engineersAsync.when(
                  loading: () => const LinearProgressIndicator(color: Colors.white),
                  error: (e, _) => Text('Failed to load engineers: $e', style: AppText.error),
                  data: (engineers) {
                    if (widget.isEditing && !_engineerResolved) {
                      _engineerResolved = true;
                      for (final e in engineers) {
                        if (e.id == widget.clinic!.responsibleEngineerId) {
                          _selectedEngineer = e;
                          break;
                        }
                      }
                    }
                    return DropdownButtonFormField<EngineerModel>(
                      initialValue: _selectedEngineer,
                      decoration: glassInputDecoration('').copyWith(labelText: null),
                      dropdownColor: AppGlassColors.baseDark,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      iconEnabledColor: Colors.white70,
                      hint: const Text('Select engineer', style: TextStyle(color: Colors.white54)),
                      isExpanded: true,
                      items: [
                        // اختيار "None" يزيل المهندس المسؤول (يُرسل responsible_engineer: null)
                        const DropdownMenuItem<EngineerModel>(
                          value: null,
                          child: Text('— None —', style: TextStyle(color: Colors.white54)),
                        ),
                        ...engineers.map((e) => DropdownMenuItem(value: e, child: Text(e.displayName))),
                      ],
                      onChanged: (value) => setState(() => _selectedEngineer = value),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('Cancel'),
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
                : Text(widget.isEditing ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }
}