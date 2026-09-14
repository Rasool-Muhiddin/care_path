/// Clinic model — matches ClinicSerializer in devices/serializers.py (fields = "__all__")
class ClinicModel {
  final int id;
  final String name;
  final String address;
  final String phoneNumber;
  final String contactPerson;
  final int? responsibleEngineerId;

  const ClinicModel({
    required this.id,
    required this.name,
    required this.address,
    required this.phoneNumber,
    required this.contactPerson,
    this.responsibleEngineerId,
  });

  factory ClinicModel.fromJson(Map<String, dynamic> json) {
    return ClinicModel(
      id: json['id'] as int,
      name: json['name'] as String,
      address: json['address'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? '',
      contactPerson: json['contact_person'] as String? ?? '',
      responsibleEngineerId: json['responsible_engineer'] as int?,
    );
  }
}

/// Payload for creating/editing a clinic
class ClinicPayload {
  final String name;
  final String address;
  final String phoneNumber;
  final String contactPerson;
  final int? responsibleEngineerId;

  const ClinicPayload({
    required this.name,
    this.address = '',
    this.phoneNumber = '',
    this.contactPerson = '',
    this.responsibleEngineerId,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'phone_number': phoneNumber,
        'contact_person': contactPerson,
        if (responsibleEngineerId != null) 'responsible_engineer': responsibleEngineerId,
      };
}