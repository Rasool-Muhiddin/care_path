import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../engineer_providers.dart';
import '../models/device_type_model.dart';
import 'add_device_type_dialog.dart';

/// Device Types tab — list of device types with a FAB to add a new one.
///
/// Hosted inside [EngineerHomeScreen]'s `TabBarView`, which already
/// wraps the whole engineer section in a single [AppGradientBackground] —
/// this tab stays transparent on purpose so that shared background shows
/// through instead of stacking a second one on top.
class DeviceTypesTab extends ConsumerWidget {
  const DeviceTypesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(deviceTypesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddDeviceTypeDialog(context),
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Type'),
      ),
      body: RefreshIndicator(
        color: AppGlassColors.baseDark,
        backgroundColor: Colors.white,
        onRefresh: () async => ref.invalidate(deviceTypesListProvider),
        child: typesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
          error: (error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(deviceTypesListProvider),
          ),
          data: (types) {
            if (types.isEmpty) {
              return const EmptyView(icon: Icons.category_outlined, color: AppAccent.device, message: 'No device types yet — tap "New Type" to get started');
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
              children: [
                SectionHeader(
                  icon: Icons.category_outlined,
                  color: AppAccent.device,
                  title: 'Device Types',
                  subtitleSpans: [
                    TextSpan(
                      text: '${types.length}',
                      style: TextStyle(
                        color: AppAccent.device,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(color: AppAccent.device.withValues(alpha: 0.55), blurRadius: 14),
                        ],
                      ),
                    ),
                    const TextSpan(text: ' device types'),
                  ],
                ),
                const SizedBox(height: 12),
                _DeviceTypesGroup(types: types),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// All device-type rows grouped inside a single glass panel, separated
/// by thin translucent dividers instead of one card per type.
class _DeviceTypesGroup extends StatelessWidget {
  const _DeviceTypesGroup({required this.types});
  final List<DeviceTypeModel> types;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < types.length; i++) ...[
            _DeviceTypeTile(type: types[i]),
            if (i != types.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _DeviceTypeTile extends StatelessWidget {
  const _DeviceTypeTile({required this.type});
  final DeviceTypeModel type;

  @override
  Widget build(BuildContext context) {
    final badgeColor = type.isActive ? AppAccent.device : Colors.white38;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          IconBadge(icon: Icons.category, color: badgeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.name, style: AppText.tileTitle),
                if (type.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(type.description, style: AppText.tileSubtitle),
                ],
              ],
            ),
          ),
          if (!type.isActive) ...[
            // Plain Container instead of Chip — Chip's built-in Material
            // surface can wash out a custom color depending on the app's
            // theme, which caused an unreadable pill elsewhere before.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Text(
                'Inactive',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white70),
            tooltip: 'Edit',
            onPressed: () => showEditDeviceTypeDialog(context, type),
          ),
        ],
      ),
    );
  }
}

