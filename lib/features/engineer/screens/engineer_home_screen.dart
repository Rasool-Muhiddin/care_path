import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import 'clinics_tab.dart';
import 'device_types_tab.dart';
import 'devices_tab.dart';
import 'overview_tab.dart';

/// Category accent colors — every screen picks its palette from here so
/// data reads by color instead of a flat, uniform white. Used here to
/// tint each tab's icon by what it manages.
class _Accent {
  static const Color doctor = Color(0xFF5AC8FA);
  static const Color patient = Color(0xFF34D399);
  static const Color caseC = Color(0xFFFBBF24);
  static const Color device = Color(0xFFA78BFA);
  static const Color unlinked = Color(0xFFF87171);
  static const Color clinic = Color(0xFF22D3EE);
}

/// A TabBar tab with a fixed-color icon (from [_Accent]) next to the
/// label, instead of an icon that just follows the selected/unselected
/// label color like a plain [Tab] would.
class _AccentTab extends StatelessWidget {
  const _AccentTab({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

/// Engineer's home screen — operational overview plus management tabs.
///
/// This screen owns the single [AppGradientBackground] for the whole
/// engineer section — [OverviewTab], [DevicesTab], [ClinicsTab] and
/// [DeviceTypesTab] should NOT wrap themselves in another
/// [AppGradientBackground] (that would stack two translucent gradients
/// and look darker/muddier than intended). Give each tab a transparent
/// `Scaffold`/background instead and let this screen's gradient show
/// through.
class EngineerHomeScreen extends ConsumerStatefulWidget {
  const EngineerHomeScreen({super.key});

  @override
  ConsumerState<EngineerHomeScreen> createState() => _EngineerHomeScreenState();
}

class _EngineerHomeScreenState extends ConsumerState<EngineerHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final username = authState is AuthAuthenticated ? authState.user.username : '';

    final appBar = AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      title: Text('Eng. $username', style: const TextStyle(color: Colors.white)),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () => ref.read(authStateProvider.notifier).logout(),
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: Colors.white,
        indicatorWeight: 2,
        tabs: const [
          _AccentTab(icon: Icons.dashboard_outlined, color: _Accent.clinic, label: 'Overview'),
          _AccentTab(icon: Icons.memory_outlined, color: _Accent.device, label: 'Devices'),
          _AccentTab(icon: Icons.local_hospital_outlined, color: _Accent.clinic, label: 'Clinics'),
          _AccentTab(icon: Icons.category_outlined, color: _Accent.device, label: 'Device Types'),
        ],
      ),
    );

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: appBar,
        body: AppGradientBackground(
          // extendBodyBehindAppBar lets the gradient run all the way up
          // behind the transparent AppBar (no seam) — but that also means
          // the body no longer knows the AppBar's height on its own, so
          // the TabBarView's content needs an explicit top padding equal
          // to (status bar + AppBar + TabBar) or it renders underneath
          // the title/tabs, as it did before this fix.
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + appBar.preferredSize.height,
            ),
            child: TabBarView(
              controller: _tabController,
              children: [
                OverviewTab(),
                DevicesTab(),
                ClinicsTab(),
                DeviceTypesTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}