import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ltr_scope.dart';
import '../engineer_providers.dart';
import '../models/device_type_model.dart';

/// Dialog to quickly add a new device type (Type A/B/C...).
/// Only name + description + active toggle for now — setup_schema
/// fields aren't defined yet, so it's left as {} on the backend by
/// default and can be filled in later without changing this dialog.
Future<bool?> showAddDeviceTypeDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => const _AddDeviceTypeDialog(),
  );
}

class _AddDeviceTypeDialog extends ConsumerStatefulWidget {
  const _AddDeviceTypeDialog();

  @override
  ConsumerState<_AddDeviceTypeDialog> createState() => _AddDeviceTypeDialogState();
}

class _AddDeviceTypeDialogState extends ConsumerState<_AddDeviceTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isActive = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(engineerRepositoryProvider).createDeviceType(
            DeviceTypePayload(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              isActive: _isActive,
            ),
          );
      ref.invalidate(deviceTypesListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LtrScope(
      child: AlertDialog(
      title: const Text('New Device Type'),
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
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Type A',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 4),
              Text(
                'Setup fields for this type can be defined later once finalized.',
                style: Theme.of(context).textTheme.bodySmall,
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
              : const Text('Create'),
        ),
      ],
      ),
    );
  }
}