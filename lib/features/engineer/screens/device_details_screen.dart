import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../doctor/models/case_model.dart' show CaseStatus;
import '../engineer_providers.dart';
import '../models/case_summary_model.dart';
import '../models/engineer_device_model.dart';
import 'add_device_screen.dart';

/// Shared text styles for this screen's glass surfaces (white-on-navy).
class _Txt {
  static const sectionTitleMedium = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const label = TextStyle(color: Colors.white54, fontSize: 13);
  static const body = TextStyle(color: Colors.white, fontSize: 14);
  static const hint = TextStyle(color: Colors.white54, fontSize: 13);
}

/// Device details screen — opened by tapping a device in the Devices
/// tab. Shows the device's own info plus every Case that has ever been
/// linked to it (patient, doctor, diagnosis, status, session count) —
/// so the engineer can follow up on where each physical device went.
class DeviceDetailsScreen extends ConsumerStatefulWidget {
  const DeviceDetailsScreen({super.key, required this.device});

  final EngineerDeviceModel device;

  @override
  ConsumerState<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends ConsumerState<DeviceDetailsScreen> {
  late EngineerDeviceModel _device = widget.device;

  Future<void> _editDevice() async {
    final updated = await Navigator.of(context).push<EngineerDeviceModel>(
      MaterialPageRoute(builder: (_) => AddDeviceScreen(device: _device)),
    );
    if (updated != null && mounted) setState(() => _device = updated);
  }

  @override
  Widget build(BuildContext context) {
    final casesAsync = ref.watch(casesForDeviceProvider(_device.id));

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(_device.serialNumber, style: const TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: _editDevice,
            ),
          ],
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: RefreshIndicator(
              color: AppGlassColors.baseDark,
              backgroundColor: Colors.white,
              onRefresh: () async => ref.invalidate(casesForDeviceProvider(_device.id)),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _DeviceInfoCard(device: _device),
                  const SizedBox(height: 24),
                  const Text('Linked Cases', style: _Txt.sectionTitleMedium),
                  const SizedBox(height: 8),
                  casesAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Failed to load cases: $e',
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                    data: (cases) {
                      if (cases.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'This device has never been linked to a case yet.',
                            style: _Txt.hint,
                          ),
                        );
                      }
                      return Column(
                        children: cases.map((c) => _CaseCard(caseSummary: c)).toList(),
                      );
                    },
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

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.device});
  final EngineerDeviceModel device;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Type', value: device.deviceTypeName ?? '—'),
          _InfoRow(label: 'Clinic', value: device.clinicName ?? '—'),
          _InfoRow(label: 'Status', value: device.status.label),
          if (device.installedAt != null)
            _InfoRow(
              label: 'Installed',
              value:
                  '${device.installedAt!.year}/${device.installedAt!.month.toString().padLeft(2, '0')}/${device.installedAt!.day.toString().padLeft(2, '0')}',
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: _Txt.label)),
          Expanded(child: Text(value, style: _Txt.body)),
        ],
      ),
    );
  }
}

class _CaseCard extends ConsumerWidget {
  const _CaseCard({required this.caseSummary});
  final CaseSummaryModel caseSummary;

  /// Solid accent color per status — used for the leading icon and the
  /// status pill's text/border. Kept as-is from the original design so
  /// case status stays visually distinguishable at a glance.
  Color _statusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.inTreatment:
        return Colors.greenAccent;
      case CaseStatus.underEvaluation:
        return Colors.orangeAccent;
      case CaseStatus.newCase:
        return Colors.lightBlueAccent;
      case CaseStatus.closed:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsCountAsync = ref.watch(sessionsCountForCaseProvider(caseSummary.id));
    final statusColor = _statusColor(caseSummary.status);

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.18),
          child: Icon(Icons.person, color: statusColor),
        ),
        title: Text(
          caseSummary.patientName.isNotEmpty
              ? caseSummary.patientName
              : 'Patient #${caseSummary.id}',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${caseSummary.diagnosisType.label} • Dr. ${caseSummary.doctorName ?? '—'}',
              style: _Txt.hint,
            ),
            sessionsCountAsync.when(
              loading: () => const Text('Loading sessions...', style: _Txt.hint),
              error: (_, __) => const Text('Sessions: —', style: _Txt.hint),
              data: (count) => Text('Sessions logged: $count', style: _Txt.hint),
            ),
          ],
        ),
        isThreeLine: true,
        // Plain Container instead of Chip — Chip's built-in Material
        // surface can wash out a custom backgroundColor depending on the
        // app's theme (this is what made the contact-person pill in the
        // Clinics tab unreadable before it was switched to a Container).
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            caseSummary.status.label,
            style: TextStyle(fontSize: 12, color: statusColor),
          ),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(caseId: caseSummary.id)),
        ),
      ),
    );
  }
}