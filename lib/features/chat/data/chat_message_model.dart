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
  final int senderId;
  final String senderName;
  final String? senderRole;
  final InquiryType inquiryType;
  final String text;
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
    required this.createdAt,
    required this.isRead,
    required this.isMine,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) => ChatMessageModel(
        id: json['id'],
        caseId: json['case'],
        senderId: json['sender'],
        senderName: json['sender_name'] ?? '',
        senderRole: json['sender_role'],
        inquiryType: InquiryType.fromApiValue(json['inquiry_type'] as String?),
        text: json['text'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
        isRead: json['is_read'] ?? false,
        isMine: json['is_mine'] ?? false,
      );
}
