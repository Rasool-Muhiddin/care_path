// كل ما يخص الملفات في الرسائل الصوتية حسب المنصة: مسار التسجيل وإعداده،
// تجهيز الرفع، حذف التسجيل، الـ cache، والمشغّل. أندرويد/iOS بملفات
// (dart:io + path_provider)؛ الويب بلا نظام ملفات (blob بالذاكرة).
export 'voice_platform_io.dart' if (dart.library.js_interop) 'voice_platform_web.dart';
