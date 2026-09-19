/// سجل ملاحظة تطور — يطابق CaseProgressNoteSerializer في
/// cases/serializers.py. كل إدخال يمثّل فحصاً واحداً بتاريخه، وليس
/// حقلاً واحداً يُستبدل في كل مرة — حتى يقدر الطبيب يقارن التطور بين
/// فحص وآخر.
class CaseProgressNoteModel {
  final int id;
  final int caseId;
  final int? authorId;
  final String authorName;
  final String note;
  final int sessionsCompletedSnapshot;
  final int? totalSessionsPlannedSnapshot;
  final DateTime createdAt;

  const CaseProgressNoteModel({
    required this.id,
    required this.caseId,
    this.authorId,
    required this.authorName,
    required this.note,
    required this.sessionsCompletedSnapshot,
    this.totalSessionsPlannedSnapshot,
    required this.createdAt,
  });

  factory CaseProgressNoteModel.fromJson(Map<String, dynamic> json) {
    return CaseProgressNoteModel(
      id: json['id'] as int,
      caseId: json['case'] as int,
      authorId: json['author'] as int?,
      authorName: json['author_name'] as String? ?? '',
      note: json['note'] as String? ?? '',
      sessionsCompletedSnapshot: json['sessions_completed_snapshot'] as int? ?? 0,
      totalSessionsPlannedSnapshot: json['total_sessions_planned_snapshot'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// بيانات إضافة ملاحظة تطور جديدة — case + note فقط؛ اللقطات
/// (sessions_completed_snapshot...) تُحسب تلقائياً بالـ backend.
class NewCaseProgressNotePayload {
  final int caseId;
  final String note;

  const NewCaseProgressNotePayload({
    required this.caseId,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'case': caseId,
        'note': note,
      };
}