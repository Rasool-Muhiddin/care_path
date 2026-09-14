import 'user_role.dart';

/// يتحقق هل مسموح لهذا الدور بالدخول إلى هذا المسار
/// المسارات مقسّمة حسب البادئة: /patient, /doctor, /engineer
/// أي مسار لا يبدأ بأحد هذه البادئات (مثل /login) يُعتبر عاماً ومسموحاً للجميع
bool isRouteAllowedForRole(String location, UserRole role) {
  if (location.startsWith('/patient')) return role == UserRole.patient;
  if (location.startsWith('/doctor')) return role == UserRole.doctor;
  if (location.startsWith('/engineer')) return role == UserRole.engineer;
  return true; // مسار عام (login, register, splash...)
}

/// المسارات العامة التي لا تحتاج تسجيل دخول
const publicRoutes = ['/login', '/register'];

bool isPublicRoute(String location) {
  return publicRoutes.any((r) => location.startsWith(r));
}
