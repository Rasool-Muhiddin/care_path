import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// IBM Plex Sans Arabic (OFL، web/fonts/): عربي ولاتيني في خط واحد، فلا
/// يرسم المتصفح النص العربي متأخراً بانتظار خط احتياطي من Google Fonts.
const String webFontFamily = 'AxonWeb';

const _files = [
  'fonts/IBMPlexSansArabic-Regular.ttf',
  'fonts/IBMPlexSansArabic-SemiBold.ttf',
  'fonts/IBMPlexSansArabic-Bold.ttf',
];

/// قبل runApp: الملفات الثلاثة بالتوازي، نسبةً إلى <base href> (/app/).
/// فشل التحميل لا يمنع التطبيق — يرجع للخط الاحتياطي.
Future<void> loadWebFonts() async {
  try {
    final loader = FontLoader(webFontFamily);
    for (final file in _files) {
      loader.addFont(_fetch(Uri.parse(web.document.baseURI).resolve(file).toString()));
    }
    await loader.load();
  } catch (e) {
    if (kDebugMode) debugPrint('Web font load failed: $e');
  }
}

Future<ByteData> _fetch(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) throw StateError('HTTP ${response.status} for $url');
  final buffer = (await response.arrayBuffer().toDart).toDart;
  return ByteData.view(buffer);
}
