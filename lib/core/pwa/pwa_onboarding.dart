import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../notifications/web_push.dart';
import '../permissions/user_role.dart';
import '../update/web_update.dart';
import '../update/web_update_provider.dart';
import 'pwa_status.dart';

/// نصوص الإشعارات: عربي للمريض، إنجليزي للطبيب/المهندس (نفس تقسيم
/// SettingsStrings). شرح التثبيت قبل الدخول عربي دائماً.
class PwaNotificationStrings {
  const PwaNotificationStrings({
    required this.direction,
    required this.promptTitle,
    required this.promptBody,
    required this.enable,
    required this.later,
    required this.bannerOff,
    required this.bannerEnable,
    required this.bannerDenied,
    required this.bannerInstall,
    required this.bannerHow,
    required this.bannerOldIos,
    required this.bannerUnsupported,
    required this.updateAvailable,
    required this.update,
  });

  final TextDirection direction;
  final String promptTitle;
  final String promptBody;
  final String enable;
  final String later;
  final String bannerOff;
  final String bannerEnable;
  final String bannerDenied;
  final String bannerInstall;
  final String bannerHow;
  final String bannerOldIos;
  final String bannerUnsupported;

  // تنبيه "يتوفر إصدار جديد" (web_update_provider.dart)
  final String updateAvailable;
  final String update;

  static const ar = PwaNotificationStrings(
    direction: TextDirection.rtl,
    promptTitle: 'فعّل الإشعارات',
    promptBody: 'لتصلك رسائل الطبيب والمهندس وتذكير تسجيل النوبات فوراً، فعّل الإشعارات.',
    enable: 'تفعيل الإشعارات',
    later: 'لاحقاً',
    bannerOff: 'الإشعارات غير مفعّلة — لن تصلك تنبيهات الرسائل الجديدة.',
    bannerEnable: 'تفعيل',
    bannerDenied: 'الإشعارات محظورة. فعّلها من إعدادات iPhone ← الإشعارات ← Axon.',
    bannerInstall: 'ثبّت التطبيق على الشاشة الرئيسية لتصلك الإشعارات.',
    bannerHow: 'كيف؟',
    bannerOldIos: 'جهازك لا يدعم إشعارات التطبيق (يتطلب iOS 16.4 أو أحدث).',
    bannerUnsupported: 'هذا المتصفح لا يدعم الإشعارات.',
    updateAvailable: 'يتوفر إصدار جديد من التطبيق.',
    update: 'تحديث',
  );

  static const en = PwaNotificationStrings(
    direction: TextDirection.ltr,
    promptTitle: 'Turn on notifications',
    promptBody: 'Get alerted to new messages from patients and colleagues right away.',
    enable: 'Enable notifications',
    later: 'Not now',
    bannerOff: "Notifications are off — you won't be alerted to new messages.",
    bannerEnable: 'Enable',
    bannerDenied: 'Notifications are blocked. Turn them on in iPhone Settings → Notifications → Axon.',
    bannerInstall: 'Add the app to your Home Screen to get notifications.',
    bannerHow: 'How?',
    bannerOldIos: 'This iPhone does not support app notifications (iOS 16.4 or later is required).',
    bannerUnsupported: 'This browser does not support notifications.',
    updateAvailable: 'A new version is available.',
    update: 'Update',
  );
}

const _teal = Color(0xFF1ABC9C);
const _navy = Color(0xFF0A1628);
const _warning = Color(0xFFB45309);

/// يلف التطبيق كله (MaterialApp.builder). أندرويد/iOS الأصليان: الطفل كما هو.
/// على الويب البنية ثابتة دائماً (Stack/Column) وما يتغير هو محتوى الطبقات
/// فقط — كي لا يُعاد بناء الراوتر وتضيع الشاشة الحالية عند ظهور تنبيه أو اختفائه.
class PwaOnboardingGate extends ConsumerStatefulWidget {
  const PwaOnboardingGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PwaOnboardingGate> createState() => _PwaOnboardingGateState();
}

class _PwaOnboardingGateState extends ConsumerState<PwaOnboardingGate> {
  bool _installDismissed = false;
  bool _showInstallGuide = false;
  bool _promptDismissed = false;
  bool _enabling = false;
  bool _updating = false;

  Future<void> _update() async {
    setState(() => _updating = true);
    await reloadToNewWebVersion();
  }

  Future<void> _enable() async {
    setState(() => _enabling = true);
    // أول ما يحدث: طلب الإذن داخل اللمسة نفسها (enableNotifications)
    await ref.read(pwaStatusProvider.notifier).enableNotifications();
    if (mounted) {
      setState(() {
        _enabling = false;
        _promptDismissed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pwa = ref.watch(pwaStatusProvider);
    if (!pwa.isWeb) return widget.child;

    final auth = ref.watch(authStateProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    final strings = user?.role == UserRole.patient ? PwaNotificationStrings.ar : PwaNotificationStrings.en;
    final showBanner = user != null && pwa.notificationsOff;
    final showPrompt = showBanner && !_promptDismissed && pwa.permission == WebPushPermission.notAsked;
    final showGuide = (pwa.needsInstall && !_installDismissed) || _showInstallGuide;
    // بلا تسجيل دخول أيضاً: لا داعي لبقاء شاشة الدخول قديمة
    final showUpdate = ref.watch(webUpdateProvider);

    return Stack(
      children: [
        Column(
          children: [
            if (showUpdate)
              _UpdateBanner(strings: strings, busy: _updating, onUpdate: _update),
            if (showBanner)
              // التنبيه الأول أخذ مسافة شريط الحالة (SafeArea) بالفعل
              MediaQuery.removePadding(
                context: context,
                removeTop: showUpdate,
                child: _NotificationsBanner(
                  status: pwa,
                  strings: strings,
                  busy: _enabling,
                  onEnable: _enable,
                  onHowToInstall: () => setState(() => _showInstallGuide = true),
                ),
              ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: showBanner || showUpdate,
                child: widget.child,
              ),
            ),
          ],
        ),
        if (showPrompt && !showGuide)
          _NotificationsPrompt(
            strings: strings,
            busy: _enabling,
            onEnable: _enable,
            onLater: () => setState(() => _promptDismissed = true),
          ),
        if (showGuide)
          Positioned.fill(
            child: InstallGuideScreen(
              onContinue: () => setState(() {
                _installDismissed = true;
                _showInstallGuide = false;
              }),
            ),
          ),
      ],
    );
  }
}

class _NotificationsBanner extends StatelessWidget {
  const _NotificationsBanner({
    required this.status,
    required this.strings,
    required this.busy,
    required this.onEnable,
    required this.onHowToInstall,
  });

  final PwaStatus status;
  final PwaNotificationStrings strings;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onHowToInstall;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final (String text, String? action, VoidCallback? onAction) = switch (status.permission) {
      WebPushPermission.notAsked => (s.bannerOff, s.bannerEnable, onEnable),
      WebPushPermission.denied => (s.bannerDenied, null, null),
      WebPushPermission.unsupported when status.isIPhone && !status.installed =>
        (s.bannerInstall, s.bannerHow, onHowToInstall),
      WebPushPermission.unsupported when status.isIPhone => (s.bannerOldIos, null, null),
      _ => (s.bannerUnsupported, null, null),
    };
    return Directionality(
      textDirection: s.direction,
      child: Material(
        color: _warning,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.notifications_off_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
                ),
                if (action != null)
                  busy
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "يتوفر إصدار جديد — تحديث": غير حاجب، فوق كل الشاشات. الضغط يفعّل
/// الـ service worker الجديد ويعيد تحميل الصفحة (reloadToNewWebVersion).
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.strings, required this.busy, required this.onUpdate});
  final PwaNotificationStrings strings;
  final bool busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: strings.direction,
      child: Material(
        color: _teal,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.system_update_outlined, color: _navy, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.updateAvailable,
                    style: const TextStyle(color: _navy, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
                  ),
                ),
                busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _navy),
                        ),
                      )
                    : TextButton(
                        onPressed: onUpdate,
                        style: TextButton.styleFrom(foregroundColor: _navy),
                        child: Text(strings.update, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsPrompt extends StatelessWidget {
  const _NotificationsPrompt({
    required this.strings,
    required this.busy,
    required this.onEnable,
    required this.onLater,
  });

  final PwaNotificationStrings strings;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Positioned.fill(
      child: Directionality(
        textDirection: s.direction,
        child: Material(
          color: Colors.black54,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notifications_active_outlined, color: _teal, size: 44),
                        const SizedBox(height: 14),
                        Text(
                          s.promptTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.promptBody,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _teal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: busy ? null : onEnable,
                            child: Text(s.enable, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : onLater,
                          style: TextButton.styleFrom(foregroundColor: Colors.white70),
                          child: Text(s.later),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شرح التثبيت على iPhone (Safari ← مشاركة ← إضافة إلى الشاشة الرئيسية).
/// يظهر في Safari قبل أي شيء، ومن جديد عبر "كيف؟" في تنبيه الإشعارات.
class InstallGuideScreen extends StatelessWidget {
  const InstallGuideScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: _navy,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.add_to_home_screen, color: _teal, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'ثبّت Axon على iPhone',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'أضف التطبيق إلى الشاشة الرئيسية ليعمل كتطبيق كامل وتصلك إشعارات الرسائل الجديدة وتذكير النوبات:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.6),
                    ),
                    const SizedBox(height: 22),
                    const _Step(
                      number: 1,
                      icon: Icons.ios_share,
                      text: 'اضغط زر المشاركة في Safari (أسفل الشاشة، أو بجانب شريط العنوان).',
                    ),
                    const _Step(
                      number: 2,
                      icon: Icons.add_box_outlined,
                      text: 'مرّر للأسفل واختر «إضافة إلى الشاشة الرئيسية».',
                    ),
                    const _Step(
                      number: 3,
                      icon: Icons.touch_app_outlined,
                      text: 'اضغط «إضافة»، ثم افتح Axon من أيقونته على الشاشة الرئيسية وسجّل الدخول.',
                    ),
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _warning.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _warning.withValues(alpha: 0.6)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.notifications_off_outlined, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'الإشعارات لا تعمل إلا بعد التثبيت على الشاشة الرئيسية، وتتطلب iOS 16.4 أو أحدث.',
                                style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextButton(
                      onPressed: onContinue,
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('المتابعة في المتصفح بدون إشعارات'),
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

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.text});
  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: _teal,
            child: Text('$number', style: const TextStyle(color: _navy, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.55)),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: Colors.white70, size: 24),
        ],
      ),
    );
  }
}
