/// نموذج جلسة العلاج — يطابق TreatmentSessionSerializer في treatments/serializers.py
///
/// ملاحظات مطابقة مؤكدة من الـ serializer الفعلي:
/// - `device` يرجّع UUID تبع الجهاز (Device.id)، وليس serial_number —
///   لعرض السيريال نمبر بالواجهة لاحقاً، إما نجلبه من /api/devices/
///   بشكل منفصل، أو نضيف device_serial_number كحقل بالـ serializer.
/// - `performed_by` للقراءة فقط (يُملأ تلقائياً من الـ backend)، ومرفق
///   معه `performed_by_name` الجاهز للعرض المباشر.
/// - لا يوجد `updated_at`، فقط `created_at`.
class SessionModel {
  final int id;
  final int caseId;
  final String? deviceId;
  final int? performedById; // null إذا حُذف حساب من نفّذ الجلسة (SET_NULL)
  final String performedByName;
  final DateTime sessionDate;
  final int? durationMinutes;
  final Map<String, dynamic> deviceParameters;
  final String doctorNotes;
  final String patientResponse;
  final DateTime createdAt;

  const SessionModel({
    required this.id,
    required this.caseId,
    this.deviceId,
    this.performedById,
    required this.performedByName,
    required this.sessionDate,
    this.durationMinutes,
    required this.deviceParameters,
    required this.doctorNotes,
    required this.patientResponse,
    required this.createdAt,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] as int,
      caseId: json['case'] as int,
      deviceId: json['device'] as String?,
      performedById: json['performed_by'] as int?,
      performedByName: json['performed_by_name'] as String? ?? '',
      sessionDate: DateTime.parse(json['session_date'] as String).toLocal(),
      durationMinutes: json['duration_minutes'] as int?,
      deviceParameters:
          (json['device_parameters'] as Map<String, dynamic>?) ?? const {},
      doctorNotes: json['doctor_notes'] as String? ?? '',
      patientResponse: json['patient_response'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

/// بيانات إنشاء جلسة جديدة من طرف المريض — يرسلها المريض نفسه عند
/// الضغط على "إنهاء الجلسة"، بدون تقييم أو ملاحظة (patient_response
/// اختياري بالـ backend). لا تحتوي doctor_notes إطلاقاً (لا كمفتاح
/// حتى لو فاضي)، لأن الـ backend يرفض أي طلب من مريض يحتوي هذا المفتاح
/// ضمن بيانات الطلب، بغض النظر عن قيمته.
class NewSessionPayload {
  final int caseId;

  const NewSessionPayload({required this.caseId});

  Map<String, dynamic> toJson() => {
        'case': caseId,
        // UTC صريحاً: بدون إزاحة كان الخادم يفسّر الوقت المحلي على أنه UTC.
        // (للمريض يستبدله الخادم بوقته هو على أي حال)
        'session_date': DateTime.now().toUtc().toIso8601String(),
      };
}
