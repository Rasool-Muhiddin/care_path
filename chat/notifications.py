from accounts.models import User, UserRole

from .models import ChatMessage, InquiryType


def _recipients_for(message: ChatMessage):
    case = message.case
    if message.inquiry_type == InquiryType.TECHNICAL:
        clinic = case.device.clinic if case.device else None
        engineer = clinic.responsible_engineer if clinic else None
        if engineer:
            return [engineer]
        # حالة غير مسندة لمهندس مسؤول بعد — نفس منطق عدّاد غير
        # المقروء في UnreadCountView: تظهر لكل المهندسين إلى حين
        # ربطها بعيادة/مهندس مسؤول.
        return list(User.objects.filter(role=UserRole.ENGINEER))
    return [case.patient, case.doctor]


def notify_new_message(message: ChatMessage) -> None:
    """يُستدعى بعد حفظ رسالة جديدة — يرسل إشعار push لكل طرف آخر في القناة."""
    from notifications.services import send_push_to_users  # يتجنّب استيراد دائري عند إقلاع التطبيقات

    recipients = [
        u for u in _recipients_for(message) if u is not None and u.pk != message.sender_id
    ]
    if not recipients:
        return

    preview = message.text if len(message.text) <= 80 else message.text[:77] + "…"
    send_push_to_users(
        recipients,
        title=f"رسالة جديدة من {message.sender.get_full_name() or message.sender.username}",
        body=preview,
        data={
            "type": "chat_message",
            "case_id": message.case_id,
            "inquiry_type": message.inquiry_type,
        },
    )
