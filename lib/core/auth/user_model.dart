import '../permissions/user_role.dart';

/// نموذج المستخدم — يطابق استجابة /api/auth/me/ في Django backend
class UserModel {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final UserRole role;
  final String? phoneNumber;
  final String? specialty; // يُستخدم فقط للطبيب عادة

  /// مهندس بصلاحية مدير (يُضبط من Django admin فقط). يُستخدم لإخفاء ما لا
  /// يملكه المهندس العادي؛ السيرفر هو من يفرض الصلاحيات فعلياً.
  final bool isManager;

  const UserModel({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
    required this.email,
    required this.role,
    this.phoneNumber,
    this.specialty,
    this.isManager = false,
  });

  /// الاسم الكامل، أو اسم المستخدم إن كان الاسمان فارغين (مثل get_full_name في Django)
  String get fullName {
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    return name.isEmpty ? username : name;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: UserRole.fromApiValue(json['role'] as String),
      phoneNumber: json['phone_number'] as String?,
      specialty: json['specialty'] as String?,
      isManager: json['is_manager'] as bool? ?? false,
    );
  }
}