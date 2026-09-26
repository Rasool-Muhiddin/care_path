import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import '../models/device_type_model.dart';
import '../models/engineer_device_model.dart';

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const sectionTitle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const warning = TextStyle(color: Colors.orangeAccent, fontSize: 13);
}

/// New / Edit device screen — the engineer enters serial number, type,
/// clinic (optional), status, and install date.
/// Pass [device] to edit an existing device instead of creating one.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key, this.device});

  /// When non-null, the screen opens in edit mode pre-filled with this
  /// device's data and submits a PATCH instead of a POST.
  final EngineerDeviceModel? device;

  bool get isEditing => device != null;

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _serialNumberController =
      TextEditingController(text: widget.device?.serialNumber ?? '');

  DeviceTypeModel? _selectedDeviceType;
  ClinicModel? _selectedClinic;
  late DeviceStatus _selectedStatus = widget.device?.status ?? DeviceStatus.active;
  late DateTime? _installedAt = widget.device?.installedAt;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _serialNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickInstalledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _installedAt ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _installedAt = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final payload = NewDevicePayload(
        serialNumber: _serialNumberController.text.trim(),
        deviceTypeId: _selectedDeviceType?.id,
        clinicId: _selectedClinic?.id,
        status: _selectedStatus,
        installedAt: _installedAt,
      );
      final repo = ref.read(engineerRepositoryProvider);
      final saved = widget.isEditing
          ? await repo.updateDevice(widget.device!.id, payload)
          : await repo.createDevice(payload);
      ref.invalidate(devicesListProvider);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypesAsync = ref.watch(deviceTypesListProvider);
    final clinicsAsync = ref.watch(clinicsListProvider);

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(
            widget.isEditing ? 'Edit Device' : 'New Device',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  TextFormField(
                    controller: _serialNumberController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: glassInputDecoration('Serial Number'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),

                  // --- Device type ---
                  const Text('Device Type', style: _Txt.sectionTitle),
                  const SizedBox(height: 8),
                  deviceTypesAsync.when(
                    loading: () => const LinearProgressIndicator(color: Colors.white),
                    error: (e, _) => Text('Failed to load device types: $e',
                        style: const TextStyle(color: Colors.redAccent)),
                    data: (types) {
                      if (types.isEmpty) {
                        return const Text(
                          'No device types yet — add one from the "Device Types" tab first.',
                          style: _Txt.warning,
                        );
                      }
                      // Resolve the device's current type to a matching item in
                      // the loaded list on first build (edit mode only).
                      if (widget.isEditing && _selectedDeviceType == null) {
                        for (final t in types) {
                          if (t.id == widget.device!.deviceTypeId) {
                            _selectedDeviceType = t;
                            break;
                          }
                        }
                      }
                      return DropdownButtonFormField<DeviceTypeModel>(
                        initialValue: _selectedDeviceType,
                        decoration: glassInputDecoration('').copyWith(labelText: null),
                        dropdownColor: AppGlassColors.baseDark,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        iconEnabledColor: Colors.white70,
                        hint: const Text('Select device type', style: TextStyle(color: Colors.white54)),
                        isExpanded: true,
                        items: types
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                            .toList(),
                        onChanged: (value) => setState(() => _selectedDeviceType = value),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- Clinic (optional) ---
                  const Text('Clinic (optional)', style: _Txt.sectionTitle),
                  const SizedBox(height: 8),
                  clinicsAsync.when(
                    loading: () => const LinearProgressIndicator(color: Colors.white),
                    error: (e, _) => Text('Failed to load clinics: $e',
                        style: const TextStyle(color: Colors.redAccent)),
                    data: (clinics) {
                      if (widget.isEditing && _selectedClinic == null) {
                        for (final c in clinics) {
                          if (c.id == widget.device!.clinicId) {
                            _selectedClinic = c;
                            break;
                          }
                        }
                      }
                      return DropdownButtonFormField<ClinicModel>(
                        initialValue: _selectedClinic,
                        decoration: glassInputDecoration('').copyWith(labelText: null),
                        dropdownColor: AppGlassColors.baseDark,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        iconEnabledColor: Colors.white70,
                        hint: const Text('Select clinic', style: TextStyle(color: Colors.white54)),
                        isExpanded: true,
                        items: clinics
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                            .toList(),
                        onChanged: (value) => setState(() => _selectedClinic = value),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- Status ---
                  const Text('Status', style: _Txt.sectionTitle),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<DeviceStatus>(
                    initialValue: _selectedStatus,
                    decoration: glassInputDecoration('').copyWith(labelText: null),
                    dropdownColor: AppGlassColors.baseDark,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    iconEnabledColor: Colors.white70,
                    items: DeviceStatus.values
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedStatus = value!),
                  ),
                  const SizedBox(height: 20),

                  // --- Installed date ---
                  const Text('Installed Date (optional)', style: _Txt.sectionTitle),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickInstalledDate,
                    child: InputDecorator(
                      decoration: glassInputDecoration('').copyWith(labelText: null),
                      child: Text(
                        _installedAt == null
                            ? 'Select date'
                            : '${_installedAt!.year}/${_installedAt!.month.toString().padLeft(2, '0')}/${_installedAt!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: _installedAt == null ? Colors.white54 : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ),
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              widget.isEditing ? 'Save Changes' : 'Save Device',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}