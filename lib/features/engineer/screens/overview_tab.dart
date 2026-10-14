import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
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
  static const error = TextStyle(color: Color(0xFFF87171), fontSize: 13);
}

/// Thin divider used between grouped list rows inside a single glass
/// panel, instead of one card per row.
Widget _groupDivider() => Divider(
      height: 1,
      thickness: 1,
      indent: 14,
      endIndent: 14,
      color: Colors.white.withValues(alpha: 0.08),
    );

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
    // الحالة المغلقة تعني أن الجهاز أُرجع، فيعود متاحاً لمريض آخر
    final linkedDeviceIds = cases
        .where((caseModel) => caseModel.status != CaseStatus.closed)
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
              _MetricCard(
                icon: Icons.medical_services_outlined,
                label: 'Doctors',
                value: doctors.length,
                color: AppAccent.doctor,
              ),
              _MetricCard(
                icon: Icons.people_outline,
                label: 'Patients',
                value: patients.length,
                color: AppAccent.patient,
              ),
              _MetricCard(
                icon: Icons.assignment_outlined,
                label: 'Cases',
                value: cases.length,
                color: AppAccent.caseC,
              ),
              _MetricCard(
                icon: Icons.memory_outlined,
                label: 'Devices',
                value: devices.length,
                color: AppAccent.device,
              ),
              _MetricCard(
                icon: Icons.link_off_outlined,
                label: 'Unlinked devices',
                value: unlinkedDevices.length,
                color: AppAccent.unlinked,
              ),
              _MetricCard(
                icon: Icons.local_hospital_outlined,
                label: 'Clinics',
                value: clinics.length,
                color: AppAccent.clinic,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const SectionHeader(
            titleStyle: _Txt.sectionTitle, subtitleStyle: _Txt.sectionSubtitle,
            icon: Icons.medical_services_outlined,
            color: AppAccent.doctor,
            title: 'Doctors and patient treatment summaries',
            subtitleText: 'Each patient shows treatment days since the case was opened and completed sessions.',
          ),
          const SizedBox(height: 10),
          if (doctors.isEmpty && _unassignedCases.isEmpty)
            const _EmptyCard(message: 'No doctors have been added yet.')
          else
            _DoctorsGroup(
              doctors: doctors,
              casesForDoctor: _casesForDoctor,
              unassignedCases: _unassignedCases,
            ),
          const SizedBox(height: 24),
          const SectionHeader(
            titleStyle: _Txt.sectionTitle, subtitleStyle: _Txt.sectionSubtitle,
            icon: Icons.local_hospital_outlined,
            color: AppAccent.clinic,
            title: 'Clinics',
            subtitleText: 'Devices and active patient cases at each clinic.',
          ),
          const SizedBox(height: 10),
          if (clinics.isEmpty)
            const _EmptyCard(message: 'No clinics have been added yet.')
          else
            _ClinicsGroup(
              clinics: clinics,
              deviceCountFor: (clinicId) =>
                  devices.where((device) => device.clinicId == clinicId).length,
              patientCountFor: (clinicId) => _patientsAtClinic(clinicId).length,
            ),
          const SizedBox(height: 24),
          const SectionHeader(
            titleStyle: _Txt.sectionTitle, subtitleStyle: _Txt.sectionSubtitle,
            icon: Icons.link_off_outlined,
            color: AppAccent.unlinked,
            title: 'Devices not linked to a patient',
            subtitleText: 'Available devices that are not used by any case.',
          ),
          const SizedBox(height: 10),
          if (unlinkedDevices.isEmpty)
            const _EmptyCard(message: 'All devices are linked to patient cases.')
          else
            _DevicesGroup(devices: unlinkedDevices),
          const SizedBox(height: 24),
          const SectionHeader(
            titleStyle: _Txt.sectionTitle, subtitleStyle: _Txt.sectionSubtitle,
            icon: Icons.person_off_outlined,
            color: AppAccent.unlinked,
            title: 'Patients without a case',
            subtitleText: 'Registered patients who have not yet been linked to a doctor or device.',
          ),
          const SizedBox(height: 10),
          if (unassignedPatients.isEmpty)
            const _EmptyCard(message: 'All registered patients have a case.')
          else
            _PatientsWithoutCaseGroup(patients: unassignedPatients),
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
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158,
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: _Txt.metricValue.copyWith(
                      shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 14)],
                    ),
                  ),
                  Text(label, style: _Txt.metricLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// All doctors (plus an optional "cases without a doctor" entry)
/// grouped inside a single glass panel, separated by thin dividers,
/// instead of one card per doctor.
class _DoctorsGroup extends StatelessWidget {
  const _DoctorsGroup({
    required this.doctors,
    required this.casesForDoctor,
    required this.unassignedCases,
  });

  final List<DoctorModel> doctors;
  final List<CaseModel> Function(int doctorId) casesForDoctor;
  final List<CaseModel> unassignedCases;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
        ),
        child: Column(
          children: [
            for (var i = 0; i < doctors.length; i++) ...[
              _DoctorTile(doctor: doctors[i], cases: casesForDoctor(doctors[i].id)),
              if (i != doctors.length - 1 || unassignedCases.isNotEmpty) _groupDivider(),
            ],
            if (unassignedCases.isNotEmpty)
              ExpansionTile(
                iconColor: Colors.white70,
                collapsedIconColor: Colors.white70,
                leading: IconBadge(icon: Icons.person_off_outlined, color: AppAccent.unlinked),
                title: const Text('Cases without a doctor', style: _Txt.tileTitle),
                subtitle: Text('${unassignedCases.length} case(s) need assignment', style: _Txt.tileSubtitle),
                children: [
                  for (var i = 0; i < unassignedCases.length; i++) ...[
                    _PatientTreatmentTile(caseModel: unassignedCases[i]),
                    if (i != unassignedCases.length - 1) _groupDivider(),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({required this.doctor, required this.cases});
  final DoctorModel doctor;
  final List<CaseModel> cases;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      iconColor: Colors.white70,
      collapsedIconColor: Colors.white70,
      leading: IconBadge(icon: Icons.person_outline, color: AppAccent.doctor),
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
          for (var i = 0; i < cases.length; i++) ...[
            _PatientTreatmentTile(caseModel: cases[i]),
            if (i != cases.length - 1) _groupDivider(),
          ],
      ],
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
      leading: IconBadge(icon: Icons.person, color: AppAccent.patient),
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

/// All clinics grouped inside a single glass panel, separated by thin
/// translucent dividers instead of one card per clinic.
class _ClinicsGroup extends StatelessWidget {
  const _ClinicsGroup({
    required this.clinics,
    required this.deviceCountFor,
    required this.patientCountFor,
  });

  final List<ClinicModel> clinics;
  final int Function(int clinicId) deviceCountFor;
  final int Function(int clinicId) patientCountFor;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < clinics.length; i++) ...[
            _ClinicRow(
              clinic: clinics[i],
              deviceCount: deviceCountFor(clinics[i].id),
              patientCount: patientCountFor(clinics[i].id),
            ),
            if (i != clinics.length - 1) _groupDivider(),
          ],
        ],
      ),
    );
  }
}

class _ClinicRow extends StatelessWidget {
  const _ClinicRow({required this.clinic, required this.deviceCount, required this.patientCount});
  final ClinicModel clinic;
  final int deviceCount;
  final int patientCount;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconBadge(icon: Icons.local_hospital_outlined, color: AppAccent.clinic),
      title: Text(clinic.name, style: _Txt.tileTitle),
      subtitle: Text(
        [
          '$deviceCount devices',
          '$patientCount patients',
          if (clinic.address.isNotEmpty) clinic.address,
        ].join(' • '),
        style: _Txt.tileSubtitle,
      ),
    );
  }
}

/// All unlinked devices grouped inside a single glass panel, separated
/// by thin translucent dividers instead of one card per device.
class _DevicesGroup extends StatelessWidget {
  const _DevicesGroup({required this.devices});
  final List<EngineerDeviceModel> devices;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < devices.length; i++) ...[
            _DeviceRow(device: devices[i]),
            if (i != devices.length - 1) _groupDivider(),
          ],
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});
  final EngineerDeviceModel device;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconBadge(icon: Icons.memory_outlined, color: AppAccent.unlinked),
      title: Text(device.serialNumber, style: _Txt.tileTitle),
      subtitle: Text(
        [
          if (device.clinicName != null) device.clinicName!,
          device.status.label,
        ].join(' • '),
        style: _Txt.tileSubtitle,
      ),
    );
  }
}

/// All patients without a case grouped inside a single glass panel,
/// separated by thin translucent dividers instead of one card per
/// patient.
class _PatientsWithoutCaseGroup extends StatelessWidget {
  const _PatientsWithoutCaseGroup({required this.patients});
  final List<PatientModel> patients;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < patients.length; i++) ...[
            _PatientWithoutCaseRow(patient: patients[i]),
            if (i != patients.length - 1) _groupDivider(),
          ],
        ],
      ),
    );
  }
}

class _PatientWithoutCaseRow extends StatelessWidget {
  const _PatientWithoutCaseRow({required this.patient});
  final PatientModel patient;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconBadge(icon: Icons.person_add_alt_1_outlined, color: AppAccent.unlinked),
      title: Text(patient.displayName, style: _Txt.tileTitle),
      subtitle: Text(
        patient.phoneNumber?.isNotEmpty == true ? patient.phoneNumber! : patient.username,
        style: _Txt.tileSubtitle,
      ),
    );
  }
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
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBadge(icon: Icons.error_outline, color: AppAccent.unlinked, size: 48),
                const SizedBox(height: 14),
                Text(message, textAlign: TextAlign.center, style: _Txt.error),
                const SizedBox(height: 16),
                RetryButton(onPressed: onRetry),
              ],
            ),
          ),
        ),
      );
}