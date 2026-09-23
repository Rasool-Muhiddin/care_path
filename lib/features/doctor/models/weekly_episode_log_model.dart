/// تقرير نوبات أسبوعي — يطابق WeeklyEpisodeLogSerializer في
/// cases/serializers.py. إدخال واحد لكل أسبوع لكل حالة، يرسله المريض
/// إجبارياً (راجع CaseModel.pendingWeeklyEpisodeWeek). سجل تاريخي ثابت
/// لا يُعدَّل — تُستخدم قائمة هذي التقارير عبر الزمن لبناء الـ barplot
/// عند الطبيب (مقارنة الجلسات بالنوبات شهرياً/أسبوعياً).
class WeeklyEpisodeLogModel {
  final int id;
  final int caseId;
  final DateTime weekStartDate;
  final int episodeCount;
  final DateTime submittedAt;

  const WeeklyEpisodeLogModel({
    required this.id,
    required this.caseId,
    required this.weekStartDate,
    required this.episodeCount,
    required this.submittedAt,
  });

  factory WeeklyEpisodeLogModel.fromJson(Map<String, dynamic> json) {
    return WeeklyEpisodeLogModel(
      id: json['id'] as int,
      caseId: json['case'] as int,
      weekStartDate: DateTime.parse(json['week_start_date'] as String),
      episodeCount: json['episode_count'] as int,
      submittedAt: DateTime.parse(json['submitted_at'] as String),
    );
  }
}

/// بيانات إرسال تقرير أسبوعي جديد — case + episode_count فقط؛
/// week_start_date يُحسب تلقائياً بالـ backend (أقدم أسبوع مستحق).
class NewWeeklyEpisodeLogPayload {
  final int caseId;
  final int episodeCount;

  const NewWeeklyEpisodeLogPayload({
    required this.caseId,
    required this.episodeCount,
  });

  Map<String, dynamic> toJson() => {
        'case': caseId,
        'episode_count': episodeCount,
      };
}