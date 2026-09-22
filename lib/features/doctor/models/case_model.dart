/// Diagnosis types — matches DiagnosisType in cases/models.py
enum DiagnosisType {
  migraine('migraine', 'Migraine'),
  epilepsy('epilepsy', 'Epilepsy');

  const DiagnosisType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DiagnosisType fromApiValue(String value) =>
      DiagnosisType.values.firstWhere((e) => e.apiValue == value, orElse: () => DiagnosisType.migraine);

  /// Whether clinical detail fields (monthly episode count / duration /
  /// medications) apply to this diagnosis type. Both remaining diagnosis
  /// types (epilepsy, migraine) have clinical details.
  bool get hasClinicalDetails => true;
}

/// Disease sub-type — matches DiseaseType in cases/models.py.
/// Placeholder values (type1/type2/type3) until the real sub-types are
/// defined.
enum DiseaseType {
  type1('type1', 'Type 1'),
  type2('type2', 'Type 2'),
  type3('type3', 'Type 3');

  const DiseaseType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DiseaseType fromApiValue(String? value) =>
      DiseaseType.values.firstWhere((e) => e.apiValue == value, orElse: () => DiseaseType.type1);
}

/// Case status — matches CaseStatus in cases/models.py
enum CaseStatus {
  newCase('new', 'New'),
  underEvaluation('under_evaluation', 'Under Evaluation'),
  inTreatment('in_treatment', 'In Treatment'),
  closed('closed', 'Closed');

  const CaseStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static CaseStatus fromApiValue(String value) =>
      CaseStatus.values.firstWhere((e) => e.apiValue == value, orElse: () => CaseStatus.newCase);
}

/// Case model — matches CaseSerializer in cases/serializers.py
class CaseModel {
  final int id;
  final int patientId;
  final String patientName;
  final int? doctorId;
  final String? doctorName;
  final String? deviceId;
  final String? deviceTypeName;
  final Map<String, dynamic> deviceSetupParameters;
  final DiagnosisType diagnosisType;
  final DiseaseType? diseaseType;
  final CaseStatus status;
  final int? monthlyEpisodeCount;
  final int? episodeDurationMinutes;
  final String symptoms;
  final String currentMedications;
  final int? totalSessionsPlanned;
  final int completedSessionsCount;
  final int? remainingSessionsCount;
  final String guarantorName;
  final String guarantorAddress;
  final String guarantorPhoneNumber;
  final String guarantorEmail;
  final String initialEvaluation;
  final String treatmentPlan;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CaseModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.doctorId,
    this.doctorName,
    this.deviceId,
    this.deviceTypeName,
    required this.deviceSetupParameters,
    required this.diagnosisType,
    this.diseaseType,
    required this.status,
    this.monthlyEpisodeCount,
    this.episodeDurationMinutes,
    this.symptoms = '',
    this.currentMedications = '',
    this.totalSessionsPlanned,
    this.completedSessionsCount = 0,
    this.remainingSessionsCount,
    this.guarantorName = '',
    this.guarantorAddress = '',
    this.guarantorPhoneNumber = '',
    this.guarantorEmail = '',
    required this.initialEvaluation,
    required this.treatmentPlan,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CaseModel.fromJson(Map<String, dynamic> json) {
    return CaseModel(
      id: json['id'] as int,
      patientId: json['patient'] as int,
      patientName: json['patient_name'] as String? ?? '',
      doctorId: json['doctor'] as int?,
      doctorName: json['doctor_name'] as String?,
      deviceId: json['device'] as String?,
      deviceTypeName: json['device_type_name'] as String?,
      deviceSetupParameters:
          (json['device_setup_parameters'] as Map<String, dynamic>?) ?? const {},
      diagnosisType: DiagnosisType.fromApiValue(json['diagnosis_type'] as String),
      diseaseType: (json['disease_type'] as String?)?.isNotEmpty == true
          ? DiseaseType.fromApiValue(json['disease_type'] as String?)
          : null,
      status: CaseStatus.fromApiValue(json['status'] as String),
      monthlyEpisodeCount: json['monthly_episode_count'] as int?,
      episodeDurationMinutes: json['episode_duration_minutes'] as int?,
      symptoms: json['symptoms'] as String? ?? '',
      currentMedications: json['current_medications'] as String? ?? '',
      totalSessionsPlanned: json['total_sessions_planned'] as int?,
      completedSessionsCount: json['completed_sessions_count'] as int? ?? 0,
      remainingSessionsCount: json['remaining_sessions_count'] as int?,
      guarantorName: json['guarantor_name'] as String? ?? '',
      guarantorAddress: json['guarantor_address'] as String? ?? '',
      guarantorPhoneNumber: json['guarantor_phone_number'] as String? ?? '',
      guarantorEmail: json['guarantor_email'] as String? ?? '',
      initialEvaluation: json['initial_evaluation'] as String? ?? '',
      treatmentPlan: json['treatment_plan'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Payload for creating a new case — fields sent via POST /api/cases/
class NewCasePayload {
  final int patientId;
  final int doctorId;
  final String? deviceId;
  final Map<String, dynamic> deviceSetupParameters;
  final DiagnosisType diagnosisType;
  final DiseaseType? diseaseType;
  final int? monthlyEpisodeCount;
  final int? episodeDurationMinutes;
  final String symptoms;
  final String currentMedications;
  final int? totalSessionsPlanned;
  final String guarantorName;
  final String guarantorAddress;
  final String guarantorPhoneNumber;
  final String guarantorEmail;
  final String initialEvaluation;
  final String treatmentPlan;

  const NewCasePayload({
    required this.patientId,
    required this.doctorId,
    this.deviceId,
    this.deviceSetupParameters = const {},
    required this.diagnosisType,
    this.diseaseType,
    this.monthlyEpisodeCount,
    this.episodeDurationMinutes,
    this.symptoms = '',
    this.currentMedications = '',
    this.totalSessionsPlanned,
    this.guarantorName = '',
    this.guarantorAddress = '',
    this.guarantorPhoneNumber = '',
    this.guarantorEmail = '',
    this.initialEvaluation = '',
    this.treatmentPlan = '',
  });

  Map<String, dynamic> toJson() => {
        'patient': patientId,
        'doctor': doctorId,
        if (deviceId != null) 'device': deviceId,
        'device_setup_parameters': deviceSetupParameters,
        'diagnosis_type': diagnosisType.apiValue,
        if (diseaseType != null) 'disease_type': diseaseType!.apiValue,
        if (monthlyEpisodeCount != null) 'monthly_episode_count': monthlyEpisodeCount,
        if (episodeDurationMinutes != null) 'episode_duration_minutes': episodeDurationMinutes,
        'symptoms': symptoms,
        'current_medications': currentMedications,
        if (totalSessionsPlanned != null) 'total_sessions_planned': totalSessionsPlanned,
        'guarantor_name': guarantorName,
        'guarantor_address': guarantorAddress,
        'guarantor_phone_number': guarantorPhoneNumber,
        'guarantor_email': guarantorEmail,
        'initial_evaluation': initialEvaluation,
        'treatment_plan': treatmentPlan,
      };
}

/// Payload for updating an existing case's status, treatment plan, and
/// initial evaluation — sent via PATCH /api/cases/{id}/.
class CaseUpdatePayload {
  final CaseStatus status;
  final String treatmentPlan;
  final String initialEvaluation;
  final int? totalSessionsPlanned;

  const CaseUpdatePayload({
    required this.status,
    required this.treatmentPlan,
    required this.initialEvaluation,
    this.totalSessionsPlanned,
  });

  Map<String, dynamic> toJson() => {
        'status': status.apiValue,
        'treatment_plan': treatmentPlan,
        'initial_evaluation': initialEvaluation,
        if (totalSessionsPlanned != null) 'total_sessions_planned': totalSessionsPlanned,
      };
}