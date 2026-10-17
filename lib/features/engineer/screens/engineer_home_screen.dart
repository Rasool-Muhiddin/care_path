import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../../chat/logic/chat_notifier.dart';
import 'clinics_tab.dart';
import 'device_types_tab.dart';
import 'devices_tab.dart';
import 'messages_tab.dart';
import 'overview_tab.dart';
import '../../settings/settings_screen.dart';

/// AppBar title: a small glass-style "BME" badge (Biomedical Engineer)
/// followed by the user's name — replaces the plain "Eng. name" text.
class _BmeTitle extends StatelessWidget {
  const _BmeTitle({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    const accent = AppAccent.clinic;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: const Text(
            'BME.',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        if (username.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            // الاسم الطويل ينزل لسطر ثاني بدل ما ينقطع بـ (...)
            child: Text(
              username,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A TabBar tab with a fixed-color icon (from [AppAccent]) next to the
/// label, instead of an icon that just follows the selected/unselected
/// label color like a plain [Tab] would.
class _AccentTab extends StatelessWidget {
  const _AccentTab({required this.icon, required this.color, required this.label, this.badgeCount = 0});
  final IconData icon;
  final Color color;
  final String label;

  /// عدد يظهر بدائرة حمراء بجانب العنوان (0 = بلا شارة)
  final int badgeCount;

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
          if (badgeCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppAccent.unlinked,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Engineer's home screen — operational overview plus management tabs.
///
/// This screen owns the single [AppGradientBackground] for the whole
/// engineer section — [OverviewTab], [MessagesTab], [DevicesTab],
/// [ClinicsTab] and [DeviceTypesTab] should NOT wrap themselves in another
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
    _tabController = TabController(length: 5, vsync: this);
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
    // للمهندس: رسائل المرضى غير المقروءة في المحادثات التي يستطيع الرد فيها
    // (نفس نطاق فلتر "My clinics")
    final unreadMessages =
        (ref.watch(unreadByCaseProvider).value ?? const <int, int>{}).values.fold(0, (a, b) => a + b);

    final appBar = AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      title: _BmeTitle(username: username),
      actions: [
        // Settings (account info, log out, delete account, ...)
        SettingsButton(strings: SettingsStrings.en),
      ],
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: Colors.white,
        indicatorWeight: 2,
        tabs: [
          const _AccentTab(icon: Icons.dashboard_outlined, color: AppAccent.clinic, label: 'Overview'),
          _AccentTab(
            icon: Icons.forum_outlined,
            color: AppAccent.patient,
            label: 'Messages',
            badgeCount: unreadMessages,
          ),
          const _AccentTab(icon: Icons.memory_outlined, color: AppAccent.device, label: 'Devices'),
          const _AccentTab(icon: Icons.local_hospital_outlined, color: AppAccent.clinic, label: 'Clinics'),
          const _AccentTab(icon: Icons.category_outlined, color: AppAccent.device, label: 'Device Types'),
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
              children: const [
                OverviewTab(),
                MessagesTab(),
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