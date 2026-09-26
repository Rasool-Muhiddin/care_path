
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
