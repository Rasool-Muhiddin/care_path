import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../engineer_providers.dart';
import '../models/device_type_model.dart';

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
                const SizedBox(height: 16),
                _SectionHeader(
                  icon: Icons.toggle_on_outlined,
                  color: _Accent.device,
                  title: 'Status',
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: TextStyle(color: Colors.white)),
                  value: _isActive,
                  activeThumbColor: _Accent.device,
                  activeTrackColor: _Accent.device.withValues(alpha: 0.35),
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 4),
                Text(
                  'Setup fields for this type can be defined later once finalized.',
                  style: _Txt.body,
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