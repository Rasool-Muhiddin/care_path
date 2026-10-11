/// الأدوار — تطابق UserRole في accounts/models.py.
///
/// إضافة دور جديد هنا: قيمة في الـ enum، فرع في [homeRoute] و[fromApiValue]
/// و[displayNameAr]، ومسار GoRoute بنفس البادئة في app_router.dart. حراسة
/// المسارات (route_guard.dart) تتبع [homeRoute] تلقائياً.
enum UserRole {
  patient,
  doctor,
  engineer;

  /// يحوّل القيمة القادمة من الـ API (String) إلى enum
  /// مثال: "patient" -> UserRole.patient
  static UserRole fromApiValue(String value) {
    switch (value.toLowerCase()) {
      case 'patient':
        return UserRole.patient;
      case 'doctor':
        return UserRole.doctor;
      case 'engineer':
        return UserRole.engineer;
      default:
        throw ArgumentError('دور غير معروف من الـ API: $value');
    }
  }

  /// يحوّل الـ enum إلى القيمة التي يتوقعها الـ API
  String toApiValue() => name;

  /// المسار الجذري لهذا الدور في التطبيق (يُستخدم في الـ router والـ guards)
  String get homeRoute {
    switch (this) {
      case UserRole.patient:
        return '/patient';
      case UserRole.doctor:
        return '/doctor';
      case UserRole.engineer:
        return '/engineer';
    }
  }

  /// مسار شاشة محادثة حالة معيّنة لهذا الدور (يُستعمل عند الضغط على
  /// إشعار رسالة)، أو null إن لم يكن لهذا الدور مسار محادثة في الراوتر.
  String? chatRoute(int caseId) {
    switch (this) {
      case UserRole.patient:
      case UserRole.doctor:
      case UserRole.engineer:
        return '$homeRoute/chat/$caseId';
    }
  }

  /// اسم معروض بالعربية (للاستخدام في الواجهة لاحقاً)
  String get displayNameAr {
    switch (this) {
      case UserRole.patient:
        return 'مريض';
      case UserRole.doctor:
        return 'طبيب';
      case UserRole.engineer:
        return 'مهندس';
    }
  }
}
