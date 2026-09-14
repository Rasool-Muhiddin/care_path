import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ltr_scope.dart';
import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import '../models/device_type_model.dart';
import '../models/engineer_device_model.dart';

/// New device screen — the engineer enters serial number, model, type,
/// clinic (optional), status, install date, and notes.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialNumberController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _notesController = TextEditingController();

  DeviceTypeModel? _selectedDeviceType;
  ClinicModel? _selectedClinic;
  DeviceStatus _selectedStatus = DeviceStatus.active;
  DateTime? _installedAt;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _serialNumberController.dispose();
    _modelNameController.dispose();
    _notesController.dispose();
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
      await ref.read(engineerRepositoryProvider).createDevice(
            NewDevicePayload(
              serialNumber: _serialNumberController.text.trim(),
              modelName: _modelNameController.text.trim(),
              deviceTypeId: _selectedDeviceType?.id,
              clinicId: _selectedClinic?.id,
              status: _selectedStatus,
              installedAt: _installedAt,
              notes: _notesController.text.trim(),
            ),
          );
      ref.invalidate(devicesListProvider);
      if (mounted) Navigator.of(context).pop();
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
        appBar: AppBar(title: const Text('New Device')),
        body: Form(
          key: _formKey,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _serialNumberController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Serial Number',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _modelNameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Model Name',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),

            // --- Device type ---
            Text('Device Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            deviceTypesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Failed to load device types: $e'),
              data: (types) {
                if (types.isEmpty) {
                  return const Text(
                    'No device types yet — add one from the "Device Types" tab first.',
                    style: TextStyle(color: Colors.orange),
                  );
                }
                return DropdownButtonFormField<DeviceTypeModel>(
                  initialValue: _selectedDeviceType,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  hint: const Text('Select device type'),
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
            Text('Clinic (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            clinicsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Failed to load clinics: $e'),
              data: (clinics) => DropdownButtonFormField<ClinicModel>(
                initialValue: _selectedClinic,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Select clinic'),
                isExpanded: true,
                items: clinics
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedClinic = value),
              ),
            ),
            const SizedBox(height: 20),

            // --- Status ---
            Text('Status', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<DeviceStatus>(
              initialValue: _selectedStatus,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: DeviceStatus.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedStatus = value!),
            ),
            const SizedBox(height: 20),

            // --- Installed date ---
            Text('Installed Date (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickInstalledDate,
              child: InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(
                  _installedAt == null
                      ? 'Select date'
                      : '${_installedAt!.year}/${_installedAt!.month.toString().padLeft(2, '0')}/${_installedAt!.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- Notes ---
            Text('Notes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Device'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}