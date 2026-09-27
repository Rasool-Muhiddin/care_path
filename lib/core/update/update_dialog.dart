import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/glass_container.dart';
import 'app_version_model.dart';

/// نافذة إشعار التحديث — تُعرض من splash_screen عندما يكتشف
/// [appUpdateProvider] نسخة أحدث منشورة من لوحة الأدمن.
///
/// إن كانت [AppVersionInfo.isMandatory] مفعّلة: لا يوجد زر "لاحقاً" ولا
/// إمكانية إغلاق النافذة (لا بالضغط خارجها ولا بزر الرجوع) — المستخدم
/// يجب أن يحدّث قبل متابعة استخدام التطبيق.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.info});

  final AppVersionInfo info;

  /// يعرض النافذة وينتظر إغلاقها (فقط ممكن فعلياً إن لم يكن التحديث إلزامياً).
  static Future<void> show(BuildContext context, AppVersionInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.isMandatory,
      builder: (_) => PopScope(
        canPop: !info.isMandatory,
        child: UpdateDialog(info: info),
      ),
    );
  }

  Future<void> _openDownloadLink() async {
    final uri = Uri.tryParse(info.downloadLink);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: info.isMandatory ? 'تحديث مطلوب' : 'يتوفر تحديث جديد',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'النسخة ${info.versionName} متوفرة الآن.',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (info.releaseNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              info.releaseNotes,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (info.isMandatory) ...[
            const SizedBox(height: 14),
            const Text(
              'هذا التحديث إلزامي ولا يمكن متابعة استخدام التطبيق قبل تثبيته.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!info.isMandatory)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('لاحقاً', style: TextStyle(color: Colors.white70)),
          ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            await _openDownloadLink();
            if (!info.isMandatory && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('تحديث الآن'),
        ),
      ],
    );
  }
}
