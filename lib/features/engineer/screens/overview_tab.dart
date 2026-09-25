import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../doctor/models/case_model.dart';
import '../../doctor/models/patient_model.dart';
import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import '../models/doctor_model.dart';
import '../models/engineer_device_model.dart';
import 'engineer_patient_details_screen.dart';

/// Shared text styles for this tab's glass surfaces (white-on-navy).
class _Txt {
  static const headline = TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700);
  static const body = TextStyle(color: Colors.white70, fontSize: 13);
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700);
  static const sectionSubtitle = TextStyle(color: Colors.white70, fontSize: 12);
  static const metricValue = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const metricLabel = TextStyle(color: Colors.white70, fontSize: 12);
  static const tileTitle = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white70, fontSize: 12);
  static const chip = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600);
  static const empty = TextStyle(color: Colors.white70, fontSize: 13);
  static const error = TextStyle(color: Colors.redAccent, fontSize: 13);
}

/// لوحة متابعة المدير/المهندس. تعتمد على البيانات الفعلية التي يراها
/// المهندس في النظام، وتعرض ملخص علاج كل مريض أسفل طبيبه.
///
/// ملاحظة: هذا الويدجت يُستخدم كمحتوى تبويب (tab) ولا يملك Scaffold أو
/// AppBar خاصّين به — يُفترض أن الشاشة الأم (التي تحتضن TabBar) هي التي
/// تلفّ المحتوى بـ AppGradientBackground، تماماً مثل باقي شاشات المهندس.
/// إن لم يكن الأمر كذلك أخبرني لأضيفها هنا مباشرة.
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
      return const Center(child: CircularProgressIndicator(color: Colors.white));
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
      color: Colors.white,
      backgroundColor: AppGlassColors.baseDark,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text('System overview', style: _Txt.headline),
          const SizedBox(height: 4),
          const Text('Live operational view for the engineer account.', style: _Txt.body),
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
          const _SectionTitle(
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
          const _SectionTitle(
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
          const _SectionTitle(
            title: 'Devices not linked to a patient',
            subtitle: 'Available devices that are not used by any case.',
          ),
          const SizedBox(height: 8),
          if (unlinkedDevices.isEmpty)
            const _EmptyCard(message: 'All devices are linked to patient cases.')
          else
            ...unlinkedDevices.map((device) => _DeviceCard(device: device)),
          const SizedBox(height: 24),
          const _SectionTitle(
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
    return SizedBox(
      width: 158,
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: _Txt.metricValue),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _Txt.metricLabel),
                ],
              ),
            ),
          ],
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
          Text(title, style: _Txt.sectionTitle),
          const SizedBox(height: 2),
          Text(subtitle, style: _Txt.sectionSubtitle),
        ],
      );
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.doctor, required this.cases});
  final DoctorModel doctor;
  final List<CaseModel> cases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
          ),
          child: ExpansionTile(
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            leading: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person_outline, color: Colors.white),
            ),
            title: Text(doctor.displayName, style: _Txt.tileTitle),
            subtitle: Text(
              [
                if (doctor.specialty.isNotEmpty) doctor.specialty,
                '${cases.length} ${cases.length == 1 ? 'patient case' : 'patient cases'}',
              ].join(' • '),
              style: _Txt.tileSubtitle,
            ),
            children: [
              if (cases.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No patient cases assigned.', style: _Txt.empty),
                  ),
                )
              else
                ...cases.map((caseModel) => _PatientTreatmentTile(caseModel: caseModel)),
            ],
          ),
        ),
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
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.white24,
        child: Icon(Icons.person, color: Colors.white),
      ),
      title: Text(
        caseModel.patientName.isNotEmpty ? caseModel.patientName : 'Patient #${caseModel.patientId}',
        style: _Txt.tileTitle,
      ),
      subtitle: Text(
        [
          '${_treatmentDays} treatment days',
          '${caseModel.completedSessionsCount} completed sessions',
          if (caseModel.totalSessionsPlanned != null) '${caseModel.totalSessionsPlanned} planned',
          if (caseModel.deviceTypeName != null) caseModel.deviceTypeName!,
        ].join(' • '),
        style: _Txt.tileSubtitle,
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(caseModel.status.label, style: _Txt.chip),
      ),
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
  Widget build(BuildContext context) => GlassContainer(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            leading: const Icon(Icons.person_off_outlined, color: Colors.white),
            title: const Text('Cases without a doctor', style: _Txt.tileTitle),
            subtitle: Text('${cases.length} case(s) need assignment', style: _Txt.tileSubtitle),
            children: cases.map((caseModel) => _PatientTreatmentTile(caseModel: caseModel)).toList(),
          ),
        ),
      );
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.clinic, required this.deviceCount, required this.patientCount});
  final ClinicModel clinic;
  final int deviceCount;
  final int patientCount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassContainer(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.local_hospital_outlined, color: Colors.white),
            ),
            title: Text(clinic.name, style: _Txt.tileTitle),
            subtitle: Text(
              [
                '$deviceCount devices',
                '$patientCount patients',
                if (clinic.address.isNotEmpty) clinic.address,
              ].join(' • '),
              style: _Txt.tileSubtitle,
            ),
          ),
        ),
      );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final EngineerDeviceModel device;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassContainer(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.memory_outlined, color: Colors.white),
            ),
            title: Text(device.serialNumber, style: _Txt.tileTitle),
            subtitle: Text(
              [
                device.modelName,
                if (device.clinicName != null) device.clinicName!,
                device.status.label,
              ].join(' • '),
              style: _Txt.tileSubtitle,
            ),
          ),
        ),
      );
}

class _PatientWithoutCaseCard extends StatelessWidget {
  const _PatientWithoutCaseCard({required this.patient});
  final PatientModel patient;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassContainer(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
            ),
            title: Text(patient.displayName, style: _Txt.tileTitle),
            subtitle: Text(
              patient.phoneNumber?.isNotEmpty == true ? patient.phoneNumber! : patient.username,
              style: _Txt.tileSubtitle,
            ),
          ),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Text(message, style: _Txt.empty),
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
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: _Txt.error),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}