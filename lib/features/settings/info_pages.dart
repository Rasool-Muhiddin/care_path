import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings/app_info_texts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_container.dart';

/// In-app privacy policy (placeholder text from [AppInfoTexts]).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, required this.title, required this.direction});
  final String title;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) => _InfoPage(
        title: title,
        direction: direction,
        children: const [_ArabicBody(AppInfoTexts.privacyPolicyAr)],
      );
}

/// App name, short description, publisher and "Developed by Tera".
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key, required this.title, required this.direction});
  final String title;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final developerHost = Uri.parse(AppInfoTexts.developerUrl).host;
    return _InfoPage(
      title: title,
      direction: direction,
      children: [
        const Text(AppInfoTexts.appName, style: AppText.headline),
        const SizedBox(height: 8),
        const _ArabicBody(AppInfoTexts.aboutDescriptionAr),
        const SizedBox(height: 12),
        const _ArabicBody(AppInfoTexts.publisherAr),
        const SizedBox(height: 16),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Developed by ${AppInfoTexts.developerName} · ', style: AppText.body),
              InkWell(
                onTap: () => launchUrl(Uri.parse(AppInfoTexts.developerUrl), mode: LaunchMode.externalApplication),
                child: Text(
                  developerHost,
                  style: const TextStyle(
                    color: AppAccent.doctor,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: AppAccent.doctor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Contact / support details (placeholder text from [AppInfoTexts]).
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key, required this.title, required this.direction});
  final String title;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) => _InfoPage(
        title: title,
        direction: direction,
        children: const [_ArabicBody(AppInfoTexts.contactAr)],
      );
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({required this.title, required this.direction, required this.children});
  final String title;
  final TextDirection direction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: direction,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(color: Colors.white)),
        ),
        body: AppGradientBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The placeholder texts are Arabic for every role, so they are always RTL.
class _ArabicBody extends StatelessWidget {
  const _ArabicBody(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textDirection: TextDirection.rtl,
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.7),
      );
}
