import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
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

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const headline = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const sectionTitle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const hint = TextStyle(color: Colors.white54, fontSize: 12);
  static const body = TextStyle(color: Colors.white, fontSize: 14);
  static const tileTitle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white60, fontSize: 12);
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

/// A field label with a small colored leading icon, used above every
/// section on this form instead of a plain white caption.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.icon, this.color = _Accent.doctor});
  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(text, style: _Txt.sectionTitle),
      ],
    );
  }
}

/// Compact inline error panel for a field that failed to load its
/// options (patients/devices dropdown data), with a glass "Retry"
/// action instead of a bare line of red text.
class _InlineErrorPanel extends StatelessWidget {
  const _InlineErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _IconBadge(icon: Icons.error_outline, color: _Accent.unlinked, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: _Txt.error)),
          const SizedBox(width: 8),
          _RetryButton(onPressed: onRetry),
        ],
      ),
    );
  }
}

/// Glass-styled retry button used by every empty/error state.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
      label: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 13)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

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

  /// Dropdown-field decoration variant of [glassInputDecoration] — same
  /// look, but without a floating label since dropdowns get a section
  /// title above them instead.
  InputDecoration _dropdownDecoration({String? hint}) {
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

  Widget _sectionTitle(String text, {IconData? icon, Color color = _Accent.doctor}) =>
      _FieldLabel(text, icon: icon, color: color);

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsListProvider);
    final devicesAsync = ref.watch(devicesListProvider(null));
    final authState = ref.watch(authStateProvider);
    final doctorDisplayName =
        authState is AuthAuthenticated ? authState.user.username : '';

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('New Case', style: TextStyle(color: Colors.white)),
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // --- Attending doctor (auto-filled, read-only) ---
                  _sectionTitle('Attending Doctor', icon: Icons.badge_outlined, color: _Accent.doctor),
                  const SizedBox(height: 8),
                  GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        _IconBadge(icon: Icons.medical_services_outlined, color: _Accent.doctor, size: 32),
                        const SizedBox(width: 10),
                        Text('Dr. $doctorDisplayName', style: _Txt.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Patient selection ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Patient', icon: Icons.person_outline, color: _Accent.patient),
                      TextButton.icon(
                        onPressed: _isSubmitting ? null : _openAddPatientDialog,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        icon: Icon(Icons.person_add_alt_1, size: 18, color: _Accent.patient),
                        label: const Text('Add New Patient'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  patientsAsync.when(
                    loading: () => const LinearProgressIndicator(color: Colors.white),
                    error: (e, _) => _InlineErrorPanel(
                      message: 'Failed to load patients: $e',
                      onRetry: () => ref.invalidate(patientsListProvider),
                    ),
                    data: (patients) => DropdownButtonFormField<PatientModel>(
                      initialValue: _selectedPatient,
                      decoration: _dropdownDecoration(hint: 'Select patient'),
                      dropdownColor: AppGlassColors.baseDark,
                      style: _Txt.body,
                      iconEnabledColor: Colors.white70,
                      hint: const Text('Select patient', style: _Txt.hint),
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
                  _sectionTitle('Device (optional)', icon: Icons.memory_outlined, color: _Accent.device),
                  const SizedBox(height: 8),
                  devicesAsync.when(
                    loading: () => const LinearProgressIndicator(color: Colors.white),
                    error: (e, _) => _InlineErrorPanel(
                      message: 'Failed to load devices: $e',
                      onRetry: () => ref.invalidate(devicesListProvider(null)),
                    ),
                    data: (devices) => DropdownButtonFormField<DeviceModel>(
                      initialValue: _selectedDevice,
                      decoration: _dropdownDecoration(hint: 'Select device'),
                      dropdownColor: AppGlassColors.baseDark,
                      style: _Txt.body,
                      iconEnabledColor: Colors.white70,
                      hint: const Text('Select device', style: _Txt.hint),
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
                  _sectionTitle('Diagnosis Type', icon: Icons.category_outlined, color: _Accent.caseC),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<DiagnosisType>(
                    initialValue: _selectedDiagnosis,
                    decoration: _dropdownDecoration(),
                    dropdownColor: AppGlassColors.baseDark,
                    style: _Txt.body,
                    iconEnabledColor: Colors.white70,
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
                  _sectionTitle('${_selectedDiagnosis.label} Type', icon: Icons.category_outlined, color: _Accent.caseC),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDiseaseType,
                    decoration: _dropdownDecoration(),
                    dropdownColor: AppGlassColors.baseDark,
                    style: _Txt.body,
                    iconEnabledColor: Colors.white70,
                    items: diseaseTypeChoicesFor(_selectedDiagnosis)
                        .map((d) => DropdownMenuItem(value: d.$1, child: Text(d.$2)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedDiseaseType = value!),
                  ),
                  const SizedBox(height: 20),

                  // --- Symptoms ---
                  _sectionTitle('Symptoms', icon: Icons.sick_outlined, color: _Accent.caseC),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _symptomsController,
                    maxLines: 2,
                    style: _Txt.body,
                    cursorColor: Colors.white,
                    decoration: glassInputDecoration('', helperText: null)
                        .copyWith(hintText: 'Describe the symptoms...', labelText: null),
                  ),

                  // --- Clinical details (epilepsy/migraine only) ---
                  if (_selectedDiagnosis.hasClinicalDetails) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Diagnosis Details', icon: Icons.analytics_outlined, color: _Accent.caseC),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _monthlyEpisodeCountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: _Txt.body,
                            cursorColor: Colors.white,
                            decoration: glassInputDecoration('attack / month'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _episodeDurationController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: _Txt.body,
                            cursorColor: Colors.white,
                            decoration: glassInputDecoration('attack duration'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassContainer(
                          borderRadius: 12,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<_DurationUnit>(
                              value: _durationUnit,
                              dropdownColor: AppGlassColors.baseDark,
                              style: _Txt.body,
                              iconEnabledColor: Colors.white70,
                              items: const [
                                DropdownMenuItem(value: _DurationUnit.minutes, child: Text('min')),
                                DropdownMenuItem(value: _DurationUnit.hours, child: Text('hour')),
                              ],
                              onChanged: (value) => setState(() => _durationUnit = value!),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _medicationsController,
                      maxLines: 2,
                      style: _Txt.body,
                      cursorColor: Colors.white,
                      decoration: glassInputDecoration(
                        'Current medications',
                        helperText: null,
                      ).copyWith(hintText: 'Enter medication names...'),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // --- Initial evaluation ---
                  _sectionTitle('Initial Evaluation', icon: Icons.fact_check_outlined, color: _Accent.doctor),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _initialEvaluationController,
                    maxLines: 3,
                    style: _Txt.body,
                    cursorColor: Colors.white,
                    decoration: glassInputDecoration('')
                        .copyWith(hintText: 'Initial evaluation notes...', labelText: null),
                  ),
                  const SizedBox(height: 20),

                  // --- Total sessions planned (optional) ---
                  _sectionTitle('Total Sessions Planned (optional)',
                      icon: Icons.format_list_numbered, color: _Accent.doctor),
                  const SizedBox(height: 4),
                  const Text(
                    'Used to show the patient how many sessions remain — leave blank if not decided yet',
                    style: _Txt.hint,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _totalSessionsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: _Txt.body,
                    cursorColor: Colors.white,
                    decoration:
                        glassInputDecoration('').copyWith(hintText: 'e.g. 20', labelText: null),
                  ),
                  const SizedBox(height: 20),

                  // --- Treatment plan ---
                  Row(
                    children: [
                      _sectionTitle('Treatment Plan', icon: Icons.assignment_outlined, color: _Accent.doctor),
                      const SizedBox(width: 6),
                      const Text(
                        '(visible to patient)',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _treatmentPlanController,
                    maxLines: 3,
                    style: _Txt.body,
                    cursorColor: Colors.white,
                    decoration: glassInputDecoration('')
                        .copyWith(hintText: 'Number of sessions, daily duration...', labelText: null),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Case', style: TextStyle(fontWeight: FontWeight.w600)),
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