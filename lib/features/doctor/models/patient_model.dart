/// نموذج مختصر للمريض — يطابق PatientListSerializer في accounts/serializers.py
/// يُستخدم عند اختيار المريض لإنشاء حالة جديدة (GET /api/patients/)
class PatientModel {
  final int id;
  final String username;
  final String fullName;
  final String? phoneNumber;

  const PatientModel({
    required this.id,
    required this.username,
    required this.fullName,
    this.phoneNumber,
  });

  /// اسم للعرض بالواجهة — يستخدم الاسم الكامل إن وُجد، وإلا اليوزرنيم
  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['full_name'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
    );
  }
}