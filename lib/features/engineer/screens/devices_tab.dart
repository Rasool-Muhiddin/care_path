import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../engineer_providers.dart';
import '../models/engineer_device_model.dart';
import 'device_details_screen.dart';

/// Devices tab — list of all devices with a FAB to add a new one.
///
/// Hosted inside [EngineerHomeScreen]'s `TabBarView`, which already
/// wraps the whole engineer section in a single [AppGradientBackground] —
/// this tab stays transparent on purpose so that shared background shows
/// through instead of stacking a second one on top.
class DevicesTab extends ConsumerWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/engineer/new-device'),
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Device'),
      ),
      body: RefreshIndicator(
        color: AppGlassColors.baseDark,
        backgroundColor: Colors.white,
        onRefresh: () async => ref.invalidate(devicesListProvider),
        child: devicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
          error: (error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(devicesListProvider),
          ),
          data: (devices) {
            if (devices.isEmpty) {
              return const EmptyView(icon: Icons.memory_outlined, color: AppAccent.device, message: 'No devices yet — tap "New Device" to get started');
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
              children: [
                SectionHeader(
                  icon: Icons.memory_outlined,
                  color: AppAccent.device,
                  title: 'Devices',
                  subtitleSpans: [
                    TextSpan(
                      text: '${devices.length}',
                      style: TextStyle(
                        color: AppAccent.device,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(color: AppAccent.device.withValues(alpha: 0.55), blurRadius: 14),
                        ],
                      ),
                    ),
                    const TextSpan(text: ' registered devices'),
                  ],
                ),
                const SizedBox(height: 12),
                _DevicesGroup(devices: devices),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// All device rows grouped inside a single glass panel, separated by
/// thin translucent dividers instead of one card per device.
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
            _DeviceTile(device: devices[i]),
            if (i != devices.length - 1)
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final EngineerDeviceModel device;

  Color _statusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return Colors.greenAccent;
      case DeviceStatus.maintenance:
        return Colors.orangeAccent;
      case DeviceStatus.inactive:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(device.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DeviceDetailsScreen(device: device)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              IconBadge(icon: Icons.memory, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.serialNumber, style: AppText.tileTitle),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (device.deviceTypeName != null) device.deviceTypeName!,
                        if (device.clinicName != null) device.clinicName!,
                      ].join(' • '),
                      style: AppText.tileSubtitle,
                    ),
                  ],
                ),
              ),
              // Plain Container instead of Chip — Chip's built-in Material
              // surface can wash out a custom color depending on the app's
              // theme, which caused an unreadable pill elsewhere before.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  device.status.label,
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

