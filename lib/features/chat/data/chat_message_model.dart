enum InquiryType {
  technical,
  medical;

  String get apiValue => name;

  String get arabicLabel => switch (this) {
        InquiryType.technical => 'استفسار تقني يخص الجهاز',
        InquiryType.medical => 'استفسار طبي يخص الحالة',
      };

  static InquiryType fromApiValue(String? value) =>
      value == InquiryType.technical.apiValue
          ? InquiryType.technical
          : InquiryType.medical;
}

class ChatMessageModel {
  final int id;
  final int caseId;
  /// null = the sender's account was deleted (shown as "Deleted user").
  final int? senderId;
  final String senderName;
  final String? senderRole;
  final InquiryType inquiryType;
  /// فارغ في الرسالة الصوتية
  final String text;

  /// مسار ملف الرسالة الصوتية في الخادم (نسبي، يتطلب توكن الدخول)؛ null للنص
  final String? audioUrl;
  final int? durationSeconds;
  final DateTime createdAt;
  final bool isRead;
  final bool isMine;

  ChatMessageModel({
    required this.id,
    required this.caseId,
    required this.senderId,
    required this.senderName,
    this.senderRole,
    required this.inquiryType,
    required this.text,
    this.audioUrl,
    this.durationSeconds,
    required this.createdAt,
    required this.isRead,
    required this.isMine,
  });

  bool get isVoice => audioUrl != null;

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) => ChatMessageModel(
        id: json['id'],
        caseId: json['case'],
        senderId: json['sender'],
        senderName: json['sender_name'] ?? '',
        senderRole: json['sender_role'],
        inquiryType: InquiryType.fromApiValue(json['inquiry_type'] as String?),
        text: json['text'] ?? '',
        audioUrl: json['kind'] == 'voice' ? json['audio_url'] as String? : null,
        durationSeconds: json['duration_seconds'] as int?,
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        isRead: json['is_read'] ?? false,
        isMine: json['is_mine'] ?? false,
      );
}
