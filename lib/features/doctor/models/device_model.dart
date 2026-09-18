/// نموذج الجهاز — يطابق DeviceSerializer في devices/serializers.py
/// يُستخدم عند اختيار الجهاز لإنشاء حالة جديدة (GET /api/devices/).
/// device_type_setup_schema يحدد شكل نافذة الإعدادات الخاصة بنوع
/// الجهاز المختار (يبقى {} فارغاً إلى أن تُحدَّد الحقول لاحقاً).
class DeviceModel {
  final String id; // UUID (Device.id)
  final String serialNumber;
  final String modelName;
  final int? deviceTypeId; // DeviceType.id عادي (AutoField)، وليس UUID
  final String? deviceTypeName;
  final Map<String, dynamic> deviceTypeSetupSchema;
  final String? clinicName;
  final String status;
  final bool isAvailable;

  const DeviceModel({
    required this.id,
    required this.serialNumber,
    required this.modelName,
    this.deviceTypeId,
    this.deviceTypeName,
    required this.deviceTypeSetupSchema,
    this.clinicName,
    required this.status,
    required this.isAvailable,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      serialNumber: json['serial_number'] as String,
      modelName: json['model_name'] as String,
      deviceTypeId: json['device_type'] as int?,
      deviceTypeName: json['device_type_name'] as String?,
      deviceTypeSetupSchema:
          (json['device_type_setup_schema'] as Map<String, dynamic>?) ?? const {},
      clinicName: json['clinic_name'] as String?,
      status: json['status'] as String,
      // الـ backend يرجع is_available دائماً، لكن نتعامل بأمان مع القيمة
      // المفقودة (مثلاً استجابات قديمة مخزّنة) باعتبار الجهاز متاحاً
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }
}