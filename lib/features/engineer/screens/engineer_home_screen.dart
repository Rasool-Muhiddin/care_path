import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/ltr_scope.dart';
import 'clinics_tab.dart';
import 'device_types_tab.dart';
import 'devices_tab.dart';

/// Engineer's home screen — 3 tabs: Devices, Clinics, Device Types.
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
    _tabController = TabController(length: 3, vsync: this);
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

    return LtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Eng. $username'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authStateProvider.notifier).logout(),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Devices'),
              Tab(text: 'Clinics'),
              Tab(text: 'Device Types'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            DevicesTab(),
            ClinicsTab(),
            DeviceTypesTab(),
          ],
        ),
      ),
    );
  }
}