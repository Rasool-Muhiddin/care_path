/// Diagnosis types — matches DiagnosisType in cases/models.py
enum DiagnosisType {
  migraine('migraine', 'Migraine'),
  epilepsy('epilepsy', 'Epilepsy'),
  parkinson('parkinson', "Parkinson's Disease"),
  depression('depression', 'Depression'),
  other('other', 'Other');

  const DiagnosisType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DiagnosisType fromApiValue(String value) =>
      DiagnosisType.values.firstWhere((e) => e.apiValue == value, orElse: () => DiagnosisType.other);

  /// Whether clinical detail fields (weekly episode count / duration /
  /// medications) apply to this diagnosis type. Currently: epilepsy and
  /// migraine only.
  bool get hasClinicalDetails => this == DiagnosisType.epilepsy || this == DiagnosisType.migraine;
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
  final CaseStatus status;
  final int? weeklyEpisodeCount;
  final int? episodeDurationMinutes;
  final String currentMedications;
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
    required this.status,
    this.weeklyEpisodeCount,
    this.episodeDurationMinutes,
    this.currentMedications = '',
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
      status: CaseStatus.fromApiValue(json['status'] as String),
      weeklyEpisodeCount: json['weekly_episode_count'] as int?,
      episodeDurationMinutes: json['episode_duration_minutes'] as int?,
      currentMedications: json['current_medications'] as String? ?? '',
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
  final int? weeklyEpisodeCount;
  final int? episodeDurationMinutes;
  final String currentMedications;
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
    this.weeklyEpisodeCount,
    this.episodeDurationMinutes,
    this.currentMedications = '',
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
        if (weeklyEpisodeCount != null) 'weekly_episode_count': weeklyEpisodeCount,
        if (episodeDurationMinutes != null) 'episode_duration_minutes': episodeDurationMinutes,
        'current_medications': currentMedications,
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

  const CaseUpdatePayload({
    required this.status,
    required this.treatmentPlan,
    required this.initialEvaluation,
  });

  Map<String, dynamic> toJson() => {
        'status': status.apiValue,
        'treatment_plan': treatmentPlan,
        'initial_evaluation': initialEvaluation,
      };
}