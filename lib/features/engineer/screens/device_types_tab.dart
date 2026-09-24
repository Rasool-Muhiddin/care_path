import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engineer_providers.dart';
import '../models/device_type_model.dart';
import 'add_device_type_dialog.dart';

/// Device Types tab — list of device types with a FAB to add a new one.
class DeviceTypesTab extends ConsumerWidget {
  const DeviceTypesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(deviceTypesListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddDeviceTypeDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Type'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(deviceTypesListProvider),
        child: typesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(deviceTypesListProvider),
          ),
          data: (types) {
            if (types.isEmpty) {
              return const _EmptyView();
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: types.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _DeviceTypeTile(type: types[index]),
            );
          },
        ),
      ),
    );
  }
}

class _DeviceTypeTile extends StatelessWidget {
  const _DeviceTypeTile({required this.type});
  final DeviceTypeModel type;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (type.isActive ? Colors.green : Colors.grey).withValues(alpha: 0.15),
        child: Icon(Icons.category, color: type.isActive ? Colors.green : Colors.grey),
      ),
      title: Text(type.name),
      subtitle: type.description.isNotEmpty ? Text(type.description) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!type.isActive) ...[
            const Chip(
              label: Text('Inactive', style: TextStyle(fontSize: 12)),
              side: BorderSide.none,
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showEditDeviceTypeDialog(context, type),
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
              child: Text('No device types yet — tap "New Type" to get started'),
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