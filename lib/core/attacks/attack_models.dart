/// نوبة واحدة سجّلها المريض — يطابق AttackEventSerializer في
/// cases/serializers.py. المدة بالثواني دائماً (الشقيقة تُدخَل بالساعات
/// والدقائق، والصرع بالدقائق والثواني، وكلاهما يُحوَّل لثوانٍ).
class AttackEventModel {
  final int id;
  final int caseId;
  final DateTime occurredAt;
  final bool timeIsApproximate;
  final int durationSeconds;
  final int? severity;
  final bool tookMedication;
  final DateTime createdAt;

  const AttackEventModel({
    required this.id,
    required this.caseId,
    required this.occurredAt,
    required this.timeIsApproximate,
    required this.durationSeconds,
    this.severity,
    required this.tookMedication,
    required this.createdAt,
  });

  /// سُجّلت بعد أكثر من 24 ساعة من وقت حدوثها — محسوبة، لا يُدخلها المريض.
  static const Duration lateThreshold = Duration(hours: 24);
  bool get isLateLogged => createdAt.difference(occurredAt) > lateThreshold;

  factory AttackEventModel.fromJson(Map<String, dynamic> json) {
    return AttackEventModel(
      id: json['id'] as int,
      caseId: json['case'] as int,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      timeIsApproximate: json['time_is_approximate'] as bool? ?? false,
      durationSeconds: json['duration_seconds'] as int,
      severity: json['severity'] as int?,
      tookMedication: json['took_medication'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// بيانات تسجيل نوبة جديدة. [occurredAt] لحظة حقيقية (تُرسل UTC).
/// [severity] للشقيقة فقط — لا يُرسل المفتاح إطلاقاً للصرع.
class NewAttackEventPayload {
  final int caseId;
  final DateTime occurredAt;
  final bool timeIsApproximate;
  final int durationSeconds;
  final int? severity;
  final bool tookMedication;

  const NewAttackEventPayload({
    required this.caseId,
    required this.occurredAt,
    required this.timeIsApproximate,
    required this.durationSeconds,
    this.severity,
    required this.tookMedication,
  });

  Map<String, dynamic> toJson() => {
        'case': caseId,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'time_is_approximate': timeIsApproximate,
        'duration_seconds': durationSeconds,
        if (severity != null) 'severity': severity,
        'took_medication': tookMedication,
      };
}

/// تأكيد "لا نوبات غير مسجّلة" — يغطي الأيام السبعة الكاملة التي تسبق
/// يوم التأكيد (بتوقيت بغداد). يطابق AttackLogConfirmationSerializer.
class AttackLogConfirmationModel {
  final int id;
  final int caseId;
  final bool hadUnlogged;
  final DateTime confirmedAt;

  const AttackLogConfirmationModel({
    required this.id,
    required this.caseId,
    required this.hadUnlogged,
    required this.confirmedAt,
  });

  /// عدد الأيام (قبل يوم التأكيد) التي يغطيها التأكيد — يساوي حد
  /// التسجيل المتأخر بالسيرفر (ATTACK_MAX_DAYS_BACK).
  static const int coveredDays = 7;

  factory AttackLogConfirmationModel.fromJson(Map<String, dynamic> json) {
    return AttackLogConfirmationModel(
      id: json['id'] as int,
      caseId: json['case'] as int,
      hadUnlogged: json['had_unlogged'] as bool,
      confirmedAt: DateTime.parse(json['confirmed_at'] as String),
    );
  }
}
