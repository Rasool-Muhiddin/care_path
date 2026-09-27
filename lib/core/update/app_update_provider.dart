import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/auth_state.dart';
import 'app_update_repository.dart';
import 'app_version_model.dart';

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository(ref.read(apiClientProvider));
});

/// يفحص الخادم عند كل بدء تشغيل ويقارن أعلى version_code منشور
/// بـ buildNumber الفعلي للنسخة المثبَّتة على الجهاز (وليس رقماً ثابتاً
/// بالكود). يرجع null إن كانت النسخة الحالية محدَّثة أصلاً.
final appUpdateProvider = FutureProvider<AppVersionInfo?>((ref) async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  final latest = await ref
      .read(appUpdateRepositoryProvider)
      .fetchLatest(platform: platform);
  if (latest == null) return null;

  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

  return latest.versionCode > currentVersionCode ? latest : null;
});
