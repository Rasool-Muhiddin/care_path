import '../permissions/user_role.dart';

/// نموذج المستخدم — يطابق استجابة /api/auth/me/ في Django backend
class UserModel {
  final int id;
  final String username;
  final String email;
  final UserRole role;
  final String? phoneNumber;
  final String? specialty; // يُستخدم فقط للطبيب عادة

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.phoneNumber,
    this.specialty,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String? ?? '',
      role: UserRole.fromApiValue(json['role'] as String),
      phoneNumber: json['phone_number'] as String?,
      specialty: json['specialty'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'role': role.toApiValue(),
        'phone_number': phoneNumber,
        'specialty': specialty,
      };
}
