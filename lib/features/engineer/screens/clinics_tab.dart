import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import 'add_clinic_dialog.dart';

/// Clinics tab — list of clinics with a FAB to add a new one.
class ClinicsTab extends ConsumerWidget {
  const ClinicsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicsAsync = ref.watch(clinicsListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddClinicDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Clinic'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clinicsListProvider),
        child: clinicsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(clinicsListProvider),
          ),
          data: (clinics) {
            if (clinics.isEmpty) {
              return const _EmptyView();
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: clinics.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _ClinicTile(clinic: clinics[index]),
            );
          },
        ),
      ),
    );
  }
}

class _ClinicTile extends StatelessWidget {
  const _ClinicTile({required this.clinic});
  final ClinicModel clinic;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (clinic.address.isNotEmpty) clinic.address,
      if (clinic.phoneNumber.isNotEmpty) clinic.phoneNumber,
    ];
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
      title: Text(clinic.name),
      subtitle: subtitleParts.isNotEmpty ? Text(subtitleParts.join(' • ')) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (clinic.contactPerson.isNotEmpty) ...[
            Chip(
              label: Text(clinic.contactPerson, style: const TextStyle(fontSize: 12)),
              side: BorderSide.none,
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showEditClinicDialog(context, clinic),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No clinics yet — tap "New Clinic" to get started'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
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
          ),
        ),
      ),
    );
  }
}