// خط نسخة الويب (عربي + لاتيني) يُحمَّل قبل أول إطار. على أندرويد/iOS لا
// شيء: يبقى خط النظام كما هو، ولا تُضاف ملفات الخط إلى الـ APK.
export 'web_fonts_io.dart' if (dart.library.js_interop) 'web_fonts_web.dart';
