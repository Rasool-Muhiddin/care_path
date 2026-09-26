/// Device status — matches DeviceStatus in devices/models.py
enum DeviceStatus {
  active('active', 'Active'),
  maintenance('maintenance', 'Under Maintenance'),
  inactive('inactive', 'Inactive');

  const DeviceStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DeviceStatus fromApiValue(String value) =>
      DeviceStatus.values.firstWhere((e) => e.apiValue == value, orElse: () => DeviceStatus.active);
}

/// Full device model — matches DeviceSerializer in devices/serializers.py.
/// Used by the engineer for managing (create/edit) devices, unlike the
/// simplified read-only DeviceModel used in the doctor's case-creation flow.
class EngineerDeviceModel {
  final String id; // UUID
  final String serialNumber;
  final int? deviceTypeId;
  final String? deviceTypeName;
  final Map<String, dynamic> deviceTypeSetupSchema;
  final int? clinicId;
  final String? clinicName;
  final DeviceStatus status;
  final DateTime? installedAt;
  final DateTime? lastMaintenanceAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EngineerDeviceModel({
    required this.id,
    required this.serialNumber,
    this.deviceTypeId,
    this.deviceTypeName,
    required this.deviceTypeSetupSchema,
    this.clinicId,
    this.clinicName,
    required this.status,
    this.installedAt,
    this.lastMaintenanceAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EngineerDeviceModel.fromJson(Map<String, dynamic> json) {
    return EngineerDeviceModel(
      id: json['id'] as String,
      serialNumber: json['serial_number'] as String,
      deviceTypeId: json['device_type'] as int?,
      deviceTypeName: json['device_type_name'] as String?,
      deviceTypeSetupSchema:
          (json['device_type_setup_schema'] as Map<String, dynamic>?) ?? const {},
      clinicId: json['clinic'] as int?,
      clinicName: json['clinic_name'] as String?,
      status: DeviceStatus.fromApiValue(json['status'] as String),
      installedAt: json['installed_at'] != null ? DateTime.parse(json['installed_at'] as String) : null,
      lastMaintenanceAt: json['last_maintenance_at'] != null
          ? DateTime.parse(json['last_maintenance_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Payload for creating a new device
class NewDevicePayload {
  final String serialNumber;
  final int? deviceTypeId;
  final int? clinicId;
  final DeviceStatus status;
  final DateTime? installedAt;

  const NewDevicePayload({
    required this.serialNumber,
    this.deviceTypeId,
    this.clinicId,
    this.status = DeviceStatus.active,
    this.installedAt,
  });

  Map<String, dynamic> toJson() => {
        'serial_number': serialNumber,
        if (deviceTypeId != null) 'device_type': deviceTypeId,
        if (clinicId != null) 'clinic': clinicId,
        'status': status.apiValue,
        if (installedAt != null)
          'installed_at':
              '${installedAt!.year.toString().padLeft(4, '0')}-${installedAt!.month.toString().padLeft(2, '0')}-${installedAt!.day.toString().padLeft(2, '0')}',
      };
}