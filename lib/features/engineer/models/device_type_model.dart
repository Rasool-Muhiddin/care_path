/// Device type model — matches DeviceTypeSerializer in devices/serializers.py
class DeviceTypeModel {
  final int id;
  final String name;
  final String description;
  final Map<String, dynamic> setupSchema;
  final bool isActive;

  const DeviceTypeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.setupSchema,
    required this.isActive,
  });

  factory DeviceTypeModel.fromJson(Map<String, dynamic> json) {
    return DeviceTypeModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      setupSchema: (json['setup_schema'] as Map<String, dynamic>?) ?? const {},
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Payload for creating/editing a device type
class DeviceTypePayload {
  final String name;
  final String description;
  final bool isActive;

  const DeviceTypePayload({
    required this.name,
    this.description = '',
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'is_active': isActive,
      };
}