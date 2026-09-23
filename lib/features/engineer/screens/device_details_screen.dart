import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ltr_scope.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../doctor/models/case_model.dart' show CaseStatus;
import '../engineer_providers.dart';
import '../models/case_summary_model.dart';
import '../models/engineer_device_model.dart';

/// Device details screen — opened by tapping a device in the Devices
/// tab. Shows the device's own info plus every Case that has ever been
/// linked to it (patient, doctor, diagnosis, status, session count) —
/// so the engineer can follow up on where each physical device went.
class DeviceDetailsScreen extends ConsumerWidget {
  const DeviceDetailsScreen({super.key, required this.device});

  final EngineerDeviceModel device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final casesAsync = ref.watch(casesForDeviceProvider(device.id));

    return LtrScope(
      child: Scaffold(
        appBar: AppBar(title: Text(device.serialNumber)),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(casesForDeviceProvider(device.id)),
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _DeviceInfoCard(device: device),
            const SizedBox(height: 24),
            Text('Linked Cases', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            casesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Failed to load cases: $e', style: const TextStyle(color: Colors.red)),
              ),
              data: (cases) {
                if (cases.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('This device has never been linked to a case yet.'),
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
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.device});
  final EngineerDeviceModel device;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Model', value: device.modelName),
            _InfoRow(label: 'Type', value: device.deviceTypeName ?? '—'),
            _InfoRow(label: 'Clinic', value: device.clinicName ?? '—'),
            _InfoRow(label: 'Status', value: device.status.label),
            if (device.installedAt != null)
              _InfoRow(
                label: 'Installed',
                value:
                    '${device.installedAt!.year}/${device.installedAt!.month.toString().padLeft(2, '0')}/${device.installedAt!.day.toString().padLeft(2, '0')}',
              ),
            if (device.notes.isNotEmpty) _InfoRow(label: 'Notes', value: device.notes),
          ],
        ),
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
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _CaseCard extends ConsumerWidget {
  const _CaseCard({required this.caseSummary});
  final CaseSummaryModel caseSummary;

  Color _statusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.inTreatment:
        return Colors.green;
      case CaseStatus.underEvaluation:
        return Colors.orange;
      case CaseStatus.newCase:
        return Colors.blue;
      case CaseStatus.closed:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsCountAsync = ref.watch(sessionsCountForCaseProvider(caseSummary.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(caseSummary.status).withValues(alpha: 0.15),
          child: Icon(Icons.person, color: _statusColor(caseSummary.status)),
        ),
        title: Text(caseSummary.patientName.isNotEmpty ? caseSummary.patientName : 'Patient #${caseSummary.id}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${caseSummary.diagnosisType.label} • Dr. ${caseSummary.doctorName ?? '—'}'),
            sessionsCountAsync.when(
              loading: () => const Text('Loading sessions...'),
              error: (_, __) => const Text('Sessions: —'),
              data: (count) => Text('Sessions logged: $count'),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(caseSummary.status.label, style: const TextStyle(fontSize: 12)),
          backgroundColor: _statusColor(caseSummary.status).withValues(alpha: 0.15),
          side: BorderSide.none,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(caseId: caseSummary.id)),
        ),
      ),
    );
  }
}
