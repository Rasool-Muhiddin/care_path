import '../../doctor/models/case_model.dart' show DiagnosisType, CaseStatus;

/// Summary of a Case, as seen from the engineer's device-details screen.
/// Reuses DiagnosisType/CaseStatus enums from the doctor feature since
/// they represent the same backend concepts (cases/models.py).
class CaseSummaryModel {
  final int id;
  final String patientName;
  final String? doctorName;
  final DiagnosisType diagnosisType;
  final CaseStatus status;
  final DateTime createdAt;

  const CaseSummaryModel({
    required this.id,
    required this.patientName,
    this.doctorName,
    required this.diagnosisType,
    required this.status,
    required this.createdAt,
  });

  factory CaseSummaryModel.fromJson(Map<String, dynamic> json) {
    return CaseSummaryModel(
      id: json['id'] as int,
      patientName: json['patient_name'] as String? ?? '',
      doctorName: json['doctor_name'] as String?,
      diagnosisType: DiagnosisType.fromApiValue(json['diagnosis_type'] as String),
      status: CaseStatus.fromApiValue(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}