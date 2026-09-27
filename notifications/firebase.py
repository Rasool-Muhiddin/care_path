import logging

import firebase_admin
from django.conf import settings
from firebase_admin import credentials

logger = logging.getLogger(__name__)

_app = None
_init_failed = False


def get_firebase_app():
    """
    يهيّئ Firebase Admin SDK مرة واحدة فقط عند أول استخدام فعلي (وليس
    عند إقلاع Django) حتى لا يتعطل تشغيل السيرفر إن لم يُضبط ملف
    الاعتماد بعد. يرجع None إن تعذّرت التهيئة (يُسجَّل تحذير مرة واحدة
    فقط عبر logging) — الإرسال يفشل بصمت وقتها بدل تعطيل باقي الطلب.
    """
    global _app, _init_failed
    if _app is not None:
        return _app
    if _init_failed:
        return None

    credentials_path = getattr(settings, "FIREBASE_CREDENTIALS_PATH", None)
    if not credentials_path:
        logger.warning("FIREBASE_CREDENTIALS_PATH غير مضبوط — إشعارات FCM معطّلة.")
        _init_failed = True
        return None

    try:
        cred = credentials.Certificate(credentials_path)
        _app = firebase_admin.initialize_app(cred)
        return _app
    except Exception:
        logger.exception("تعذّرت تهيئة Firebase Admin SDK — إشعارات FCM معطّلة.")
        _init_failed = True
        return None
