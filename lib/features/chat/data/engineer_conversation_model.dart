import '../../doctor/models/case_model.dart';

/// صف في صندوق رسائل المهندس — يطابق EngineerInboxRowSerializer في
/// chat/serializers.py. محادثة تقنية واحدة (مريض ↔ مهندس) لكل حالة.
class EngineerConversationModel {
  final int caseId;
  final String patientName;
  final String? deviceSerial;
  final String? clinicName;
  final int? responsibleEngineerId;
  final String? responsibleEngineerName;
  final CaseStatus caseStatus;
  final String lastMessageText;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool canReply;

  const EngineerConversationModel({
    required this.caseId,
    required this.patientName,
    this.deviceSerial,
    this.clinicName,
    this.responsibleEngineerId,
    this.responsibleEngineerName,
    required this.caseStatus,
    required this.lastMessageText,
    this.lastMessageAt,
    required this.unreadCount,
    required this.canReply,
  });

  factory EngineerConversationModel.fromJson(Map<String, dynamic> json) => EngineerConversationModel(
        caseId: json['case'] as int,
        patientName: json['patient_name'] as String? ?? '',
        deviceSerial: json['device_serial'] as String?,
        clinicName: json['clinic_name'] as String?,
        responsibleEngineerId: json['responsible_engineer'] as int?,
        responsibleEngineerName: json['responsible_engineer_name'] as String?,
        caseStatus: CaseStatus.fromApiValue(json['case_status'] as String? ?? ''),
        lastMessageText: json['last_message_text'] as String? ?? '',
        lastMessageAt: json['last_message_at'] == null
            ? null
            : DateTime.parse(json['last_message_at'] as String).toLocal(),
        unreadCount: json['unread_count'] as int? ?? 0,
        canReply: json['can_reply'] as bool? ?? false,
      );

  ReplyRights get replyRights => ReplyRights(
        canReply: canReply,
        responsibleEngineerName: responsibleEngineerName,
      );
}

/// حق المهندس في الرد بالقناة التقنية لحالة — يطابق CaseReplyRightsView.
/// الخادم يفرض القاعدة نفسها عند الإرسال (403)؛ هذا للعرض فقط.
class ReplyRights {
  final bool canReply;
  final String? responsibleEngineerName;

  const ReplyRights({required this.canReply, this.responsibleEngineerName});

  factory ReplyRights.fromJson(Map<String, dynamic> json) => ReplyRights(
        canReply: json['can_reply'] as bool? ?? true,
        responsibleEngineerName: json['responsible_engineer_name'] as String?,
      );
}

/// صفحة من قائمة مرقّمة.
class InboxPage {
  final List<EngineerConversationModel> items;
  final bool hasNext;
  const InboxPage(this.items, this.hasNext);
}
