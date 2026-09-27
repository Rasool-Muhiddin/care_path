import logging

from firebase_admin import messaging

from .firebase import get_firebase_app
from .models import DeviceToken

logger = logging.getLogger(__name__)


def send_push_to_users(users, title: str, body: str, data: dict | None = None) -> None:
    """
    يرسل إشعار push لكل توكنات الأجهزة المسجَّلة لهذه القائمة من
    المستخدمين. لا يرفع أي استثناء عند الفشل (Firebase غير مضبوط،
    خطأ شبكة، توكن منتهي...) — الإشعار وسيلة تحسين تجربة وليس جزءاً
    حرجاً من حفظ الرسالة، فلا يجوز أن يفشل الطلب الأساسي بسببه.
    """
    app = get_firebase_app()
    if app is None:
        logger.warning("لم يُرسل إشعار: Firebase غير مهيّأ (تحقق من FIREBASE_CREDENTIALS_PATH)")
        return

    user_ids = [u.pk for u in users if u is not None]
    if not user_ids:
        logger.warning("لم يُرسل إشعار: لا يوجد مستلمون بعد استثناء المرسِل")
        return

    tokens = list(
        DeviceToken.objects.filter(user_id__in=user_ids).values_list("token", flat=True)
    )
    if not tokens:
        logger.warning(
            "لم يُرسل إشعار: لا يوجد توكن FCM مسجَّل للمستخدمين %s", user_ids
        )
        return

    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data={str(k): str(v) for k, v in (data or {}).items()},
        tokens=tokens,
    )

    try:
        response = messaging.send_each_for_multicast(message, app=app)
    except Exception:
        logger.exception("فشل إرسال إشعار FCM")
        return

    logger.warning(
        "معلومة — إشعار FCM: نجح %s من %s توكن للمستخدمين %s",
        response.success_count, len(tokens), user_ids,
    )

    # نحذف أي توكن رفضته FCM نهائياً (تطبيق أُلغي تثبيته مثلاً) حتى لا
    # نستمر بمحاولة الإرسال إليه في كل مرة.
    invalid_tokens = [
        tokens[i]
        for i, result in enumerate(response.responses)
        if not result.success and isinstance(result.exception, messaging.UnregisteredError)
    ]
    if invalid_tokens:
        DeviceToken.objects.filter(token__in=invalid_tokens).delete()