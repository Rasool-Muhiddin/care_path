import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';
import 'clinics_tab.dart';
import 'device_types_tab.dart';
import 'devices_tab.dart';
import 'overview_tab.dart';

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
          Tab(text: 'Overview'),
          Tab(text: 'Devices'),
          Tab(text: 'Clinics'),
          Tab(text: 'Device Types'),
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