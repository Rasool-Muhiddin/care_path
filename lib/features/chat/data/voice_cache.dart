import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// ملفات الرسائل الصوتية المحمّلة من الخادم، في مجلد مؤقت خاص بالتطبيق.
/// مراسلات طبية: تُمسح عند تسجيل الخروج (AuthNotifier).
class VoiceCache {
  VoiceCache._();

  static Future<Directory> _dir() async =>
      Directory('${(await getTemporaryDirectory()).path}/voice_cache');

  static Future<File> fileFor(int messageId) async {
    final dir = await _dir();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$messageId.m4a');
  }

  static Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // تنظيف فقط؛ لا يمنع الخروج
    }
  }
}
