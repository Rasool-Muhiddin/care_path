import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';
import '../models/device_model.dart';
import '../models/patient_model.dart';
import 'add_patient_dialog.dart';

/// New case screen — the doctor selects a patient from the registered
/// list, an optional device, diagnosis type, clinical details (when
/// applicable), guarantor info, and writes an initial evaluation and
/// treatment plan.
///
/// Device setup section: built dynamically from device_type_setup_schema
/// of the selected device. setup_schema is currently empty ({}) for all
/// types (fields not defined yet), so a placeholder message is shown
/// instead of actual fields — once fields are defined later in
/// DeviceType.setup_schema, this section renders on top of it without
/// changing the screen's structure.
class AddCaseScreen extends ConsumerStatefulWidget {
  const AddCaseScreen({super.key});

  @override
  ConsumerState<AddCaseScreen> createState() => _AddCaseScreenState();
}

class _AddCaseScreenState extends ConsumerState<AddCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _initialEvaluationController = TextEditingController();
  final _treatmentPlanController = TextEditingController();
  final _weeklyEpisodeCountController = TextEditingController();
  final _episodeDurationController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _guarantorNameController = TextEditingController();
  final _guarantorAddressController = TextEditingController();
  final _guarantorPhoneController = TextEditingController();
  final _guarantorEmailController = TextEditingController();

  PatientModel? _selectedPatient;
  DeviceModel? _selectedDevice;
  DiagnosisType _selectedDiagnosis = DiagnosisType.migraine;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _initialEvaluationController.dispose();
    _treatmentPlanController.dispose();
    _weeklyEpisodeCountController.dispose();
    _episodeDurationController.dispose();
    _medicationsController.dispose();
    _guarantorNameController.dispose();
    _guarantorAddressController.dispose();
    _guarantorPhoneController.dispose();
    _guarantorEmailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a patient first')),
      );
      return;
    }

    final authState = ref.read(authStateProvider);
    if (authState is! AuthAuthenticated) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(doctorRepositoryProvider).createCase(
            NewCasePayload(
              patientId: _selectedPatient!.id,
              doctorId: authState.user.id,
              deviceId: _selectedDevice?.id,
              diagnosisType: _selectedDiagnosis,
              weeklyEpisodeCount: _selectedDiagnosis.hasClinicalDetails
                  ? int.tryParse(_weeklyEpisodeCountController.text.trim())
                  : null,
              episodeDurationMinutes: _selectedDiagnosis.hasClinicalDetails
                  ? int.tryParse(_episodeDurationController.text.trim())
                  : null,
              currentMedications:
                  _selectedDiagnosis.hasClinicalDetails ? _medicationsController.text.trim() : '',
              guarantorName: _guarantorNameController.text.trim(),
              guarantorAddress: _guarantorAddressController.text.trim(),
              guarantorPhoneNumber: _guarantorPhoneController.text.trim(),
              guarantorEmail: _guarantorEmailController.text.trim(),
              initialEvaluation: _initialEvaluationController.text.trim(),
              treatmentPlan: _treatmentPlanController.text.trim(),
            ),
          );
      ref.invalidate(myCasesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openAddPatientDialog() async {
    final result = await showAddPatientDialog(context, ref);
    if (result == null) return;

    // إعادة جلب قائمة المرضى حتى يظهر بها المريض الجديد، ثم اختياره تلقائياً
    final patients = await ref.refresh(patientsListProvider.future);
    final newPatient = patients.where((p) => p.id == result.id).firstOrNull;
    if (newPatient != null && mounted) {
      setState(() => _selectedPatient = newPatient);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsListProvider);
    final devicesAsync = ref.watch(devicesListProvider(null));
    final authState = ref.watch(authStateProvider);
    final doctorDisplayName =
        authState is AuthAuthenticated ? authState.user.username : '';

    return LtrScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('New Case')),
        body: Form(
          key: _formKey,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Attending doctor (auto-filled, read-only) ---
            Text('Attending Doctor', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.medical_services_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Dr. $doctorDisplayName'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- Patient selection ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Patient', style: Theme.of(context).textTheme.titleSmall),
                TextButton.icon(
                  onPressed: _isSubmitting ? null : _openAddPatientDialog,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Add New Patient'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            patientsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Failed to load patients: $e'),
              data: (patients) => DropdownButtonFormField<PatientModel>(
                initialValue: _selectedPatient,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Select patient'),
                isExpanded: true,
                items: patients
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.displayName)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedPatient = value),
                validator: (value) => value == null ? 'This field is required' : null,
              ),
            ),
            const SizedBox(height: 20),

            // --- Device selection (optional) ---
            Text('Device (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            devicesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Failed to load devices: $e'),
              data: (devices) => DropdownButtonFormField<DeviceModel>(
                initialValue: _selectedDevice,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Select device'),
                isExpanded: true,
                items: devices
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text('${d.serialNumber} — ${d.deviceTypeName ?? "No type"}'),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _selectedDevice = value),
              ),
            ),

            // --- Device setup section (dynamic per device type) ---
            if (_selectedDevice != null) ...[
              const SizedBox(height: 12),
              _DeviceSetupSection(device: _selectedDevice!),
            ],
            const SizedBox(height: 20),

            // --- Diagnosis type ---
            Text('Diagnosis Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<DiagnosisType>(
              initialValue: _selectedDiagnosis,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: DiagnosisType.values
                  .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedDiagnosis = value!),
            ),

            // --- Clinical details (epilepsy/migraine only) ---
            if (_selectedDiagnosis.hasClinicalDetails) ...[
              const SizedBox(height: 20),
              Text('Diagnosis Details', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weeklyEpisodeCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Episodes / week',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _episodeDurationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Episode duration (min)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _medicationsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Current medications',
                  hintText: 'Enter medication names...',
                ),
              ),
            ],
            const SizedBox(height: 20),

            // --- Guarantor info ---
            Text('Guarantor Information', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Required for device purchase — the person financially/administratively responsible',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _guarantorNameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Guarantor Name',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _guarantorAddressController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Guarantor Address',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _guarantorPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Phone Number',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _guarantorEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Email',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Initial evaluation ---
            Text('Initial Evaluation', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _initialEvaluationController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Initial evaluation notes...',
              ),
            ),
            const SizedBox(height: 20),

            // --- Treatment plan ---
            Text('Treatment Plan', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _treatmentPlanController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Number of sessions, daily duration...',
              ),
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
                  : const Text('Save Case'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Shows device setup fields based on device_type_setup_schema.
/// setup_schema is currently empty for all types, so a placeholder
/// message is shown.
class _DeviceSetupSection extends StatelessWidget {
  const _DeviceSetupSection({required this.device});
  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final schema = device.deviceTypeSetupSchema;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: schema.isEmpty
          ? Text(
              'No setup fields defined yet for device type "${device.deviceTypeName ?? ''}" — '
              'they will appear here automatically once defined.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Text(
              // TODO: replace with actual fields (Text/Number/Choice) once
              // setup_schema shape is defined
              'Device type setup: $schema',
              style: Theme.of(context).textTheme.bodySmall,
            ),
    );
  }
}