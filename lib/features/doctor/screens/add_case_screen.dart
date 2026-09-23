import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';
import '../models/device_model.dart';
import '../models/patient_model.dart';
import 'add_patient_dialog.dart';

/// Duration unit for the "attack duration" field — UI-only; the value is
/// always converted to minutes before being sent to the backend
/// (Case.episode_duration_minutes stays in minutes regardless of which
/// unit the doctor picked).
enum _DurationUnit { minutes, hours }

/// New case screen — the doctor selects a patient from the registered
/// list, an optional device, diagnosis type, disease sub-type, symptoms,
/// clinical details, and writes an initial evaluation and treatment plan.
/// Guarantor / device-purchase info is handled separately by the
/// engineer's device purchase screen (not built yet), not here.
class AddCaseScreen extends ConsumerStatefulWidget {
  const AddCaseScreen({super.key});

  @override
  ConsumerState<AddCaseScreen> createState() => _AddCaseScreenState();
}

class _AddCaseScreenState extends ConsumerState<AddCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _initialEvaluationController = TextEditingController();
  final _treatmentPlanController = TextEditingController();
  final _monthlyEpisodeCountController = TextEditingController();
  final _episodeDurationController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _totalSessionsController = TextEditingController();

  PatientModel? _selectedPatient;
  DeviceModel? _selectedDevice;
  DiagnosisType _selectedDiagnosis = DiagnosisType.migraine;
  String _selectedDiseaseType = diseaseTypeChoicesFor(DiagnosisType.migraine).first.$1;
  _DurationUnit _durationUnit = _DurationUnit.minutes;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _initialEvaluationController.dispose();
    _treatmentPlanController.dispose();
    _monthlyEpisodeCountController.dispose();
    _episodeDurationController.dispose();
    _symptomsController.dispose();
    _medicationsController.dispose();
    _totalSessionsController.dispose();
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
      // Duration is always sent to the backend in minutes, regardless of
      // which unit the doctor picked in the dropdown.
      final rawDuration = int.tryParse(_episodeDurationController.text.trim());
      final episodeDurationMinutes = rawDuration == null
          ? null
          : (_durationUnit == _DurationUnit.hours ? rawDuration * 60 : rawDuration);

      await ref.read(doctorRepositoryProvider).createCase(
            NewCasePayload(
              patientId: _selectedPatient!.id,
              doctorId: authState.user.id,
              deviceId: _selectedDevice?.id,
              diagnosisType: _selectedDiagnosis,
              diseaseType: _selectedDiseaseType,
              monthlyEpisodeCount: _selectedDiagnosis.hasClinicalDetails
                  ? int.tryParse(_monthlyEpisodeCountController.text.trim())
                  : null,
              episodeDurationMinutes:
                  _selectedDiagnosis.hasClinicalDetails ? episodeDurationMinutes : null,
              symptoms: _symptomsController.text.trim(),
              currentMedications:
                  _selectedDiagnosis.hasClinicalDetails ? _medicationsController.text.trim() : '',
              totalSessionsPlanned: int.tryParse(_totalSessionsController.text.trim()),
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
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedDiagnosis = value;
                  // Sub-types are diagnosis-specific (epilepsy types vs
                  // migraine types) — reset to the new diagnosis's first
                  // option whenever the diagnosis changes.
                  _selectedDiseaseType = diseaseTypeChoicesFor(value).first.$1;
                });
              },
            ),
            const SizedBox(height: 20),

            // --- Disease sub-type — depends on the selected diagnosis:
            // epilepsy types when Epilepsy is chosen, migraine types when
            // Migraine is chosen. Placeholder values (type1/2/3) until the
            // real sub-types are defined. ---
            Text('${_selectedDiagnosis.label} Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedDiseaseType,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: diseaseTypeChoicesFor(_selectedDiagnosis)
                  .map((d) => DropdownMenuItem(value: d.$1, child: Text(d.$2)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedDiseaseType = value!),
            ),
            const SizedBox(height: 20),

            // --- Symptoms ---
            Text('Symptoms', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _symptomsController,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe the symptoms...',
              ),
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
                      controller: _monthlyEpisodeCountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'attack / month',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _episodeDurationController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'attack duration',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<_DurationUnit>(
                    value: _durationUnit,
                    items: const [
                      DropdownMenuItem(value: _DurationUnit.minutes, child: Text('min')),
                      DropdownMenuItem(value: _DurationUnit.hours, child: Text('hour')),
                    ],
                    onChanged: (value) => setState(() => _durationUnit = value!),
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

            // --- Total sessions planned (optional) ---
            Text('Total Sessions Planned (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Used to show the patient how many sessions remain — leave blank if not decided yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _totalSessionsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. 20',
              ),
            ),
            const SizedBox(height: 20),

            // --- Treatment plan ---
            Row(
              children: [
                Text('Treatment Plan', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 6),
                Text(
                  '(visible to patient)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
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