import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/auth/auth_state.dart';
import '../../core/notifications/fcm_service.dart';
import '../../core/notifications/web_push.dart';
import '../../core/permissions/user_role.dart';
import '../../core/settings/app_info_texts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/account_menu.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/glass_container.dart';
import 'info_pages.dart';

/// UI strings for the Settings screen — English for doctor/engineer,
/// Arabic for the patient (same split as [AccountMenuStrings]). The long
/// texts (privacy policy, about, contact, disclaimer) live in [AppInfoTexts].
class SettingsStrings {
  const SettingsStrings({
    required this.account,
    required this.tooltip,
    required this.title,
    required this.accountSection,
    required this.fullName,
    required this.username,
    required this.role,
    required this.roleName,
    required this.privacyPolicy,
    required this.aboutUs,
    required this.disclaimerTitle,
    required this.disclaimer,
    required this.contact,
    required this.appVersion,
    required this.logout,
    required this.dangerZone,
    required this.notifications,
    required this.notificationsOn,
    required this.notificationsEnable,
    required this.notificationsDenied,
    required this.notificationsUnsupported,
  });

  /// Strings of the delete-account flow (and the text direction).
  final AccountMenuStrings account;
  final String tooltip;
  final String title;
  final String accountSection;
  final String fullName;
  final String username;
  final String role;
  final String Function(UserRole role) roleName;
  final String privacyPolicy;
  final String aboutUs;
  final String disclaimerTitle;
  final String disclaimer;
  final String contact;
  final String appVersion;
  final String logout;
  final String dangerZone;

  // إشعارات نسخة الويب (PWA) فقط
  final String notifications;
  final String notificationsOn;
  final String notificationsEnable;
  final String notificationsDenied;
  final String notificationsUnsupported;

  TextDirection get direction => account.direction;

  static final en = SettingsStrings(
    account: AccountMenuStrings.en,
    tooltip: 'Settings',
    title: 'Settings',
    accountSection: 'Account',
    fullName: 'Full name',
    username: 'Username',
    role: 'Role',
    roleName: (role) => switch (role) {
      UserRole.patient => 'Patient',
      UserRole.doctor => 'Doctor',
      UserRole.engineer => 'Engineer',
    },
    privacyPolicy: 'Privacy policy',
    aboutUs: 'About us',
    disclaimerTitle: 'Medical disclaimer',
    disclaimer: AppInfoTexts.medicalDisclaimerEn,
    contact: 'Contact & support',
    appVersion: 'App version',
    logout: 'Log out',
    dangerZone: 'Danger zone',
    notifications: 'Notifications',
    notificationsOn: 'Notifications are on',
    notificationsEnable: 'Enable notifications',
    notificationsDenied: 'Notifications are blocked. Turn them on in iPhone Settings → Notifications → Axon.',
    notificationsUnsupported: 'Add the app to your Home Screen to receive notifications.',
  );

  static final ar = SettingsStrings(
    account: AccountMenuStrings.ar,
    tooltip: 'الإعدادات',
    title: 'الإعدادات',
    accountSection: 'الحساب',
    fullName: 'الاسم الكامل',
    username: 'اسم المستخدم',
    role: 'نوع الحساب',
    roleName: (role) => role.displayNameAr,
    privacyPolicy: 'سياسة الخصوصية',
    aboutUs: 'من نحن',
    disclaimerTitle: 'إخلاء المسؤولية الطبية',
    disclaimer: AppInfoTexts.medicalDisclaimerAr,
    contact: 'التواصل والدعم',
    appVersion: 'إصدار التطبيق',
    logout: 'تسجيل الخروج',
    dangerZone: 'منطقة الخطر',
    notifications: 'الإشعارات',
    notificationsOn: 'الإشعارات مفعّلة',
    notificationsEnable: 'تفعيل الإشعارات',
    notificationsDenied: 'الإشعارات محظورة. فعّلها من إعدادات iPhone ← الإشعارات ← Axon.',
    notificationsUnsupported: 'أضف التطبيق إلى الشاشة الرئيسية لتصلك الإشعارات.',
  );
}

/// Version of the installed app, e.g. "0.1.4 (5)".
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty ? info.version : '${info.version} (${info.buildNumber})';
});

/// AppBar icon on every role's home screen; opens [SettingsScreen].
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.strings});
  final SettingsStrings strings;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: strings.tooltip,
      icon: const Icon(Icons.account_circle_outlined, color: Colors.white),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SettingsScreen(strings: strings)),
      ),
    );
  }
}

const _danger = Color(0xFFF87171);

/// Settings, top to bottom: account info, privacy policy, about us,
/// medical disclaimer, contact, app version, log out — and, separated at
/// the very bottom, "Delete account" (the unchanged [deleteAccountFlow]).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.strings});
  final SettingsStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings;
    final auth = ref.watch(authStateProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    final version = ref.watch(appVersionProvider);

    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Directionality(
      textDirection: s.direction,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(s.title, style: const TextStyle(color: Colors.white)),
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // a) Account info (read-only)
                SectionHeader(icon: Icons.person_outline, color: AppAccent.doctor, title: s.accountSection),
                const SizedBox(height: 10),
                GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    children: [
                      _InfoRow(s.fullName, user?.fullName ?? '—'),
                      _InfoRow(s.username, user?.username ?? '—'),
                      _InfoRow(s.role, user != null ? s.roleName(user.role) : '—'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // نسخة الويب: الإشعارات تحتاج إذناً بلمسة صريحة من المستخدم
                if (kIsWeb && FcmService.instance.webPushConfigured) ...[
                  _WebNotificationsTile(strings: s),
                  const SizedBox(height: 16),
                ],

                // b) Privacy policy, c) About us
                GlassContainer(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _NavTile(
                        icon: Icons.privacy_tip_outlined,
                        title: s.privacyPolicy,
                        onTap: () => open(PrivacyPolicyScreen(title: s.privacyPolicy, direction: s.direction)),
                      ),
                      const _TileDivider(),
                      _NavTile(
                        icon: Icons.info_outline,
                        title: s.aboutUs,
                        onTap: () => open(AboutUsScreen(title: s.aboutUs, direction: s.direction)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // d) Medical disclaimer
                GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.health_and_safety_outlined, size: 20, color: AppAccent.caseC),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s.disclaimerTitle, style: AppText.tileTitle)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(s.disclaimer, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // e) Contact, f) App version, g) Log out
                GlassContainer(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _NavTile(
                        icon: Icons.support_agent_outlined,
                        title: s.contact,
                        onTap: () => open(ContactScreen(title: s.contact, direction: s.direction)),
                      ),
                      const _TileDivider(),
                      ListTile(
                        leading: const Icon(Icons.verified_outlined, color: Colors.white70),
                        title: Text(s.appVersion, style: AppText.tileTitle),
                        trailing: Text(
                          version.value ?? '…',
                          textDirection: TextDirection.ltr,
                          style: AppText.tileSubtitle,
                        ),
                      ),
                      const _TileDivider(),
                      _NavTile(
                        icon: Icons.logout,
                        title: s.logout,
                        showChevron: false,
                        onTap: () {
                          final auth = ref.read(authStateProvider.notifier);
                          Navigator.of(context).pop();
                          auth.logout();
                        },
                      ),
                    ],
                  ),
                ),

                // h) Delete account — last, separated, danger style
                const SizedBox(height: 40),
                Text(s.dangerZone, style: const TextStyle(color: _danger, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _danger.withValues(alpha: 0.5)),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: const Icon(Icons.delete_forever_outlined, color: _danger),
                      title: Text(
                        s.account.deleteAccount,
                        style: const TextStyle(color: _danger, fontWeight: FontWeight.w600),
                      ),
                      onTap: () => deleteAccountFlow(context, ref, s.account),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: AppText.body)),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: Text(value, style: AppText.tileTitle)),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, required this.onTap, this.showChevron = true});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: AppText.tileTitle),
      // chevron_right is mirrored automatically in RTL
      trailing: showChevron ? const Icon(Icons.chevron_right, color: Colors.white38) : null,
      onTap: onTap,
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: Colors.white.withValues(alpha: 0.08));
}


/// حالة إشعارات الويب وزر تفعيلها. طلب الإذن يحدث داخل لمسة الزر نفسها
/// (FcmService.enableWebPush) — شرط Safari على iPhone.
class _WebNotificationsTile extends StatefulWidget {
  const _WebNotificationsTile({required this.strings});
  final SettingsStrings strings;

  @override
  State<_WebNotificationsTile> createState() => _WebNotificationsTileState();
}

class _WebNotificationsTileState extends State<_WebNotificationsTile> {
  late WebPushPermission _permission = FcmService.instance.webPermission;
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final permission = await FcmService.instance.enableWebPush();
    if (mounted) {
      setState(() {
        _permission = permission;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final (icon, color, text) = switch (_permission) {
      WebPushPermission.granted => (Icons.notifications_active_outlined, AppAccent.caseC, s.notificationsOn),
      WebPushPermission.notAsked => (Icons.notifications_off_outlined, _danger, s.notifications),
      WebPushPermission.denied => (Icons.notifications_off_outlined, _danger, s.notificationsDenied),
      WebPushPermission.unsupported => (Icons.notifications_off_outlined, _danger, s.notificationsUnsupported),
    };
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text, style: AppText.tileTitle),
        trailing: _permission != WebPushPermission.notAsked
            ? null
            : _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(onPressed: _enable, child: Text(s.notificationsEnable)),
      ),
    );
  }
}
