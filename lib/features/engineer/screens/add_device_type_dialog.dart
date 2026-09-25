import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
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

/// Dialog to edit an existing device type — same form, pre-filled and
/// submitting a PATCH instead of a POST.
Future<bool?> showEditDeviceTypeDialog(BuildContext context, DeviceTypeModel type) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _AddDeviceTypeDialog(type: type),
  );
}

class _AddDeviceTypeDialog extends ConsumerStatefulWidget {
  const _AddDeviceTypeDialog({this.type});

  /// When non-null, the dialog opens pre-filled in edit mode.
  final DeviceTypeModel? type;

  bool get isEditing => type != null;

  @override
  ConsumerState<_AddDeviceTypeDialog> createState() => _AddDeviceTypeDialogState();
}

class _AddDeviceTypeDialogState extends ConsumerState<_AddDeviceTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.type?.name ?? '');
  late final _descriptionController = TextEditingController(text: widget.type?.description ?? '');
  late bool _isActive = widget.type?.isActive ?? true;
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
      final payload = DeviceTypePayload(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        isActive: _isActive,
      );
      final repo = ref.read(engineerRepositoryProvider);
      if (widget.isEditing) {
        await repo.updateDeviceType(widget.type!.id, payload);
      } else {
        await repo.createDeviceType(payload);
      }
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
      child: GlassDialog(
        title: widget.isEditing ? 'Edit Device Type' : 'New Device Type',
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: glassInputDecoration('Name').copyWith(hintText: 'e.g. Type A'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: glassInputDecoration('Description (optional)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: TextStyle(color: Colors.white)),
                  value: _isActive,
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.white.withValues(alpha: 0.35),
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 4),
                Text(
                  'Setup fields for this type can be defined later once finalized.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
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