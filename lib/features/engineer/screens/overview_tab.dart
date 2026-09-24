import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../doctor/models/case_model.dart';
import '../../doctor/models/patient_model.dart';
import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import '../models/doctor_model.dart';
import '../models/engineer_device_model.dart';
import 'engineer_patient_details_screen.dart';

/// لوحة متابعة المدير/المهندس. تعتمد على البيانات الفعلية التي يراها
/// المهندس في النظام، وتعرض ملخص علاج كل مريض أسفل طبيبه.
class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(doctorsListProvider);
    final patients = ref.watch(allPatientsProvider);
    final cases = ref.watch(allCasesProvider);
    final devices = ref.watch(devicesListProvider);
    final clinics = ref.watch(clinicsListProvider);
    if (doctors.isLoading ||
        patients.isLoading ||
        cases.isLoading ||
        devices.isLoading ||
        clinics.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = doctors.hasError
        ? doctors.error
        : patients.hasError
            ? patients.error
            : cases.hasError
                ? cases.error
                : devices.hasError
                    ? devices.error
                    : clinics.hasError
                        ? clinics.error
                        : null;
    if (error != null) {
      return _OverviewError(
        message: error.toString(),
        onRetry: () => _refresh(ref),
      );
    }

    return _OverviewBody(
      doctors: doctors.requireValue,
      patients: patients.requireValue,
      cases: cases.requireValue,
      devices: devices.requireValue,
      clinics: clinics.requireValue,
      onRefresh: () => _refresh(ref),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.refresh(doctorsListProvider.future),
      ref.refresh(allPatientsProvider.future),
      ref.refresh(allCasesProvider.future),
      ref.refresh(devicesListProvider.future),
      ref.refresh(clinicsListProvider.future),
    ]);
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.doctors,
    required this.patients,
    required this.cases,
    required this.devices,
    required this.clinics,
    required this.onRefresh,
  });

  final List<DoctorModel> doctors;
  final List<PatientModel> patients;
  final List<CaseModel> cases;
  final List<EngineerDeviceModel> devices;
  final List<ClinicModel> clinics;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final linkedDeviceIds = cases
        .map((caseModel) => caseModel.deviceId)
        .whereType<String>()
        .toSet();
    final unlinkedDevices = devices
        .where((device) => !linkedDeviceIds.contains(device.id))
        .toList();
    final assignedPatientIds = cases.map((caseModel) => caseModel.patientId).toSet();
    final unassignedPatients = patients
        .where((patient) => !assignedPatientIds.contains(patient.id))
        .toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('System overview', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Live operational view for the engineer account.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(icon: Icons.medical_services_outlined, label: 'Doctors', value: doctors.length),
              _MetricCard(icon: Icons.people_outline, label: 'Patients', value: patients.length),
              _MetricCard(icon: Icons.assignment_outlined, label: 'Cases', value: cases.length),
              _MetricCard(icon: Icons.memory_outlined, label: 'Devices', value: devices.length),
              _MetricCard(icon: Icons.link_off_outlined, label: 'Unlinked devices', value: unlinkedDevices.length),
              _MetricCard(icon: Icons.local_hospital_outlined, label: 'Clinics', value: clinics.length),
            ],
          ),
          const SizedBox(height: 28),
          _SectionTitle(
            title: 'Doctors and patient treatment summaries',
            subtitle: 'Each patient shows treatment days since the case was opened and completed sessions.',
          ),
          const SizedBox(height: 8),
          if (doctors.isEmpty)
            const _EmptyCard(message: 'No doctors have been added yet.')
          else
            ...doctors.map((doctor) => _DoctorCard(
                  doctor: doctor,
                  cases: _casesForDoctor(doctor.id),
                )),
          if (_unassignedCases.isNotEmpty) ...[
            const SizedBox(height: 8),
            _UnassignedCasesCard(cases: _unassignedCases),
          ],
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Clinics',
            subtitle: 'Devices and active patient cases at each clinic.',
          ),
          const SizedBox(height: 8),
          if (clinics.isEmpty)
            const _EmptyCard(message: 'No clinics have been added yet.')
          else
            ...clinics.map((clinic) => _ClinicCard(
                  clinic: clinic,
                  deviceCount: devices.where((device) => device.clinicId == clinic.id).length,
                  patientCount: _patientsAtClinic(clinic.id).length,
                )),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Devices not linked to a patient',
            subtitle: 'Available devices that are not used by any case.',
          ),
          const SizedBox(height: 8),
          if (unlinkedDevices.isEmpty)
            const _EmptyCard(message: 'All devices are linked to patient cases.')
          else
            ...unlinkedDevices.map((device) => _DeviceCard(device: device)),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Patients without a case',
            subtitle: 'Registered patients who have not yet been linked to a doctor or device.',
          ),
          const SizedBox(height: 8),
          if (unassignedPatients.isEmpty)
            const _EmptyCard(message: 'All registered patients have a case.')
          else
            ...unassignedPatients.map((patient) => _PatientWithoutCaseCard(patient: patient)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<CaseModel> _casesForDoctor(int doctorId) {
    final result = cases.where((caseModel) => caseModel.doctorId == doctorId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  List<CaseModel> get _unassignedCases =>
      cases.where((caseModel) => caseModel.doctorId == null).toList();

  Set<int> _patientsAtClinic(int clinicId) {
    final clinicDeviceIds = devices
        .where((device) => device.clinicId == clinicId)
        .map((device) => device.id)
        .toSet();
    return cases
        .where((caseModel) => caseModel.deviceId != null && clinicDeviceIds.contains(caseModel.deviceId))
        .map((caseModel) => caseModel.patientId)
        .toSet();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 158,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value', style: Theme.of(context).textTheme.titleLarge),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.doctor, required this.cases});
  final DoctorModel doctor;
  final List<CaseModel> cases;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(doctor.displayName),
        subtitle: Text([
          if (doctor.specialty.isNotEmpty) doctor.specialty,
          '${cases.length} ${cases.length == 1 ? 'patient case' : 'patient cases'}',
        ].join(' • ')),
        children: [
          if (cases.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('No patient cases assigned.')),
            )
          else
            ...cases.map((caseModel) => _PatientTreatmentTile(caseModel: caseModel)),
        ],
      ),
    );
  }
}

class _PatientTreatmentTile extends StatelessWidget {
  const _PatientTreatmentTile({required this.caseModel});
  final CaseModel caseModel;

  int get _treatmentDays {
    final elapsedDays = DateTime.now().difference(caseModel.createdAt).inDays;
    return elapsedDays < 0 ? 1 : elapsedDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: Icon(Icons.person, color: scheme.onSecondaryContainer),
      ),
      title: Text(caseModel.patientName.isNotEmpty ? caseModel.patientName : 'Patient #${caseModel.patientId}'),
      subtitle: Text([
        '${_treatmentDays} treatment days',
        '${caseModel.completedSessionsCount} completed sessions',
        if (caseModel.totalSessionsPlanned != null) '${caseModel.totalSessionsPlanned} planned',
        if (caseModel.deviceTypeName != null) caseModel.deviceTypeName!,
      ].join(' • ')),
      trailing: Chip(label: Text(caseModel.status.label), side: BorderSide.none),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EngineerPatientDetailsScreen(caseModel: caseModel),
        ),
      ),
    );
  }
}

class _UnassignedCasesCard extends StatelessWidget {
  const _UnassignedCasesCard({required this.cases});
  final List<CaseModel> cases;

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          leading: const Icon(Icons.person_off_outlined),
          title: const Text('Cases without a doctor'),
          subtitle: Text('${cases.length} case(s) need assignment'),
          children: cases.map((caseModel) => _PatientTreatmentTile(caseModel: caseModel)).toList(),
        ),
      );
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.clinic, required this.deviceCount, required this.patientCount});
  final ClinicModel clinic;
  final int deviceCount;
  final int patientCount;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
          title: Text(clinic.name),
          subtitle: Text([
            '$deviceCount devices',
            '$patientCount patients',
            if (clinic.address.isNotEmpty) clinic.address,
          ].join(' • ')),
        ),
      );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final EngineerDeviceModel device;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.memory_outlined)),
          title: Text(device.serialNumber),
          subtitle: Text([
            device.modelName,
            if (device.clinicName != null) device.clinicName!,
            device.status.label,
          ].join(' • ')),
        ),
      );
}

class _PatientWithoutCaseCard extends StatelessWidget {
  const _PatientWithoutCaseCard({required this.patient});
  final PatientModel patient;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_outlined)),
          title: Text(patient.displayName),
          subtitle: Text(patient.phoneNumber?.isNotEmpty == true ? patient.phoneNumber! : patient.username),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message),
        ),
      );
}

class _OverviewError extends StatelessWidget {
  const _OverviewError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}