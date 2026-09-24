import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      child: AlertDialog(
      title: Text(widget.isEditing ? 'Edit Clinic' : 'New Clinic'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Clinic Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              TextFormField(
                controller: _contactPersonController,
                decoration: const InputDecoration(labelText: 'Contact Person'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Responsible Engineer', style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 4),
              engineersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Failed to load engineers: $e'),
                data: (engineers) {
                  if (widget.isEditing && _selectedEngineer == null) {
                    for (final e in engineers) {
                      if (e.id == widget.clinic!.responsibleEngineerId) {
                        _selectedEngineer = e;
                        break;
                      }
                    }
                  }
                  return DropdownButtonFormField<EngineerModel>(
                  initialValue: _selectedEngineer,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  hint: const Text('Select engineer'),
                  isExpanded: true,
                  items: engineers
                      .map((e) => DropdownMenuItem(value: e, child: Text(e.displayName)))
                      .toList(),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.isEditing ? 'Save' : 'Create'),
        ),
      ],
      ),
    );
  }
}