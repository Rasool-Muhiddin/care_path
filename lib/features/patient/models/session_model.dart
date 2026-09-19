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
  final int performedById;
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
    required this.performedById,
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
      performedById: json['performed_by'] as int,
      performedByName: json['performed_by_name'] as String? ?? '',
      sessionDate: DateTime.parse(json['session_date'] as String),
      durationMinutes: json['duration_minutes'] as int?,
      deviceParameters:
          (json['device_parameters'] as Map<String, dynamic>?) ?? const {},
      doctorNotes: json['doctor_notes'] as String? ?? '',
      patientResponse: json['patient_response'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// تقييم سريع لرد فعل المريض بعد الجلسة — خيارات جاهزة + ملاحظة اختيارية
enum PatientFeeling {
  excellent('ممتاز'),
  normal('عادي'),
  difficult('سيء');

  const PatientFeeling(this.label);
  final String label;
}

/// بيانات إنشاء جلسة جديدة من طرف المريض — يرسلها المريض نفسه عند
/// الضغط على "إنهاء الجلسة". لا تحتوي doctor_notes إطلاقاً (لا كمفتاح
/// حتى لو فاضي)، لأن الـ backend يرفض أي طلب من مريض يحتوي هذا المفتاح
/// ضمن بيانات الطلب، بغض النظر عن قيمته.
class NewSessionPayload {
  final int caseId;
  final PatientFeeling feeling;
  final String? note;
  final int? durationMinutes;

  const NewSessionPayload({
    required this.caseId,
    required this.feeling,
    this.note,
    this.durationMinutes,
  });

  Map<String, dynamic> toJson() => {
        'case': caseId,
        'session_date': DateTime.now().toIso8601String(),
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'patient_response':
            (note != null && note!.trim().isNotEmpty) ? '${feeling.label}: ${note!.trim()}' : feeling.label,
      };
}