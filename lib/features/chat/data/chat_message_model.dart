class ChatMessageModel {
  final int id;
  final int caseId;
  final int senderId;
  final String senderName;
  final String? senderRole;
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
        text: json['text'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
        isRead: json['is_read'] ?? false,
        isMine: json['is_mine'] ?? false,
      );
}