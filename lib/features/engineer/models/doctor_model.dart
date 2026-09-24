/// نموذج الطبيب المختصر للوحة المهندس — يطابق DoctorListSerializer.
class DoctorModel {
  final int id;
  final String username;
  final String fullName;
  final String? phoneNumber;
  final String specialty;

  const DoctorModel({
    required this.id,
    required this.username,
    required this.fullName,
    this.phoneNumber,
    this.specialty = '',
  });

  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    return DoctorModel(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['full_name'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
      specialty: json['specialty'] as String? ?? '',
    );
  }
}
