import 'user_role.dart';

/// يتحقق هل مسموح لهذا الدور بالدخول إلى هذا المسار.
/// كل دور يملك فرعاً يبدأ بـ [UserRole.homeRoute] (/patient, /doctor, ...)؛
/// الفرع مسموح لصاحبه فقط. القائمة مشتقة من UserRole.values، فدور جديد
/// يُحرس تلقائياً بمجرد إضافته للـ enum.
/// أي مسار لا يبدأ بفرع دور (مثل /login) يُعتبر عاماً ومسموحاً للجميع.
bool isRouteAllowedForRole(String location, UserRole role) {
  for (final owner in UserRole.values) {
    if (location.startsWith(owner.homeRoute)) return owner == role;
  }
  return true; // مسار عام (login, register, splash...)
}

/// المسارات العامة التي لا تحتاج تسجيل دخول
const publicRoutes = ['/login', '/register'];

bool isPublicRoute(String location) {
  return publicRoutes.any((r) => location.startsWith(r));
}
