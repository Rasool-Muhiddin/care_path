/// Short engineer model — matches EngineerListSerializer in accounts/serializers.py
/// Used to pick a "responsible engineer" when creating a clinic.
class EngineerModel {
  final int id;
  final String username;
  final String fullName;
  final String? phoneNumber;

  const EngineerModel({
    required this.id,
    required this.username,
    required this.fullName,
    this.phoneNumber,
  });

  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  factory EngineerModel.fromJson(Map<String, dynamic> json) {
    return EngineerModel(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['full_name'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
    );
  }
}