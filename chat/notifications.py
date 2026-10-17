import logging
import threading

from django.db import connection

from accounts.models import User, UserRole

from .models import ChatMessage, InquiryType
from .permissions import responsible_engineer_of

logger = logging.getLogger(__name__)


def _recipients_for(message: ChatMessage):
    case = message.case
    if message.inquiry_type == InquiryType.TECHNICAL:
        # نفس قاعدة صاحب المحادثة (engineer_owns_chat): المهندس المسؤول عن عيادة
        # الجهاز فقط. بلا مسؤول يستطيع أي مهندس الرد، فيُشعَر الجميع.
        engineer = responsible_engineer_of(case)
        if engineer:
            return [engineer]
        return list(User.objects.filter(role=UserRole.ENGINEER, is_active=True))
    return [case.patient, case.doctor]


def notify_new_message(message: ChatMessage) -> None:
    """يُستدعى بعد حفظ رسالة جديدة — يرسل إشعار push عاماً لكل طرف آخر في القناة."""
    from notifications.services import send_push_to_users  # يتجنّب استيراد دائري عند إقلاع التطبيقات

    recipients = [
        u for u in _recipients_for(message) if u is not None and u.pk != message.sender_id
    ]
    if not recipients:
        return

    # نص عام بلا محتوى الرسالة ولا اسم المرسل: الإشعار يظهر على شاشة القفل
    # ويمر عبر خوادم Google، والمحادثة طبية. الصوتية تُذكر كنوع فقط.
    send_push_to_users(
        recipients,
        title="رسالة جديدة",
        body="رسالة صوتية جديدة" if message.is_voice else "لديك رسالة جديدة",
        data={
            "type": "chat_message",
            "case_id": message.case_id,
            "inquiry_type": message.inquiry_type,
        },
    )


def notify_message_by_id(message_id: int) -> None:
    """يُشغَّل داخل thread الخلفية: يقرأ الرسالة من جديد ويرسل الإشعار."""
    try:
        message = ChatMessage.objects.select_related(
            "sender", "case__patient", "case__doctor", "case__device__clinic__responsible_engineer"
        ).get(pk=message_id)
        notify_new_message(message)
    except Exception:
        # لا يوجد طلب ينتظر النتيجة هنا؛ نسجّل الخطأ فقط
        logger.exception("فشل إرسال إشعار الرسالة #%s", message_id)
    finally:
        # كل thread يفتح اتصال قاعدة بيانات خاصاً به — نغلقه حتى لا يتسرّب
        connection.close()


def notify_in_background(message_id: int) -> None:
    """
    يُستدعى من transaction.on_commit بعد حفظ الرسالة: يرسل الإشعار في
    thread منفصل حتى لا ينتظر الطلب اتصال FCM. thread من نوع daemon قد
    يُقطع إذا أُعيد تشغيل العامل في نفس اللحظة — الإشعار تحسين تجربة فقط.
    """
    threading.Thread(target=notify_message_by_id, args=(message_id,), daemon=True).start()
