import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../engineer_providers.dart';
import '../models/device_type_model.dart';
import 'add_device_type_dialog.dart';

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

/// Fixed text styles so every screen stays visually consistent.
class _Txt {
  static const headline = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700);
  static const sectionSubtitle = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const tileTitle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white60, fontSize: 12);
  static const body = TextStyle(color: Colors.white60, fontSize: 13);
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

/// Unified section header: colored side bar + small icon + white title
/// + a lighter subtitle line (which may contain a glowing highlight,
/// e.g. a count).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.subtitleSpans,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<InlineSpan>? subtitleSpans;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: subtitleSpans != null ? 34 : 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Txt.sectionTitle),
              if (subtitleSpans != null) ...[
                const SizedBox(height: 2),
                Text.rich(TextSpan(style: _Txt.sectionSubtitle, children: subtitleSpans)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

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
          error: (error, _) => _ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(deviceTypesListProvider),
          ),
          data: (types) {
            if (types.isEmpty) {
              return const _EmptyView();
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
              children: [
                _SectionHeader(
                  icon: Icons.category_outlined,
                  color: _Accent.device,
                  title: 'Device Types',
                  subtitleSpans: [
                    TextSpan(
                      text: '${types.length}',
                      style: TextStyle(
                        color: _Accent.device,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(color: _Accent.device.withValues(alpha: 0.55), blurRadius: 14),
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
    final badgeColor = type.isActive ? _Accent.device : Colors.white38;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _IconBadge(icon: Icons.category, color: badgeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.name, style: _Txt.tileTitle),
                if (type.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(type.description, style: _Txt.tileSubtitle),
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

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBadge(icon: Icons.category_outlined, color: _Accent.device, size: 48),
                    const SizedBox(height: 14),
                    const Text(
                      'No device types yet — tap "New Type" to get started',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
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
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBadge(icon: Icons.error_outline, color: _Accent.unlinked, size: 48),
                    const SizedBox(height: 14),
                    Text(message, textAlign: TextAlign.center, style: _Txt.error),
                    const SizedBox(height: 16),
                    _RetryButton(onPressed: onRetry),
                  ],
                ),
              ),
            ),
          ),
        ),
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
      icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
      label: const Text('Retry', style: TextStyle(color: Colors.white)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}