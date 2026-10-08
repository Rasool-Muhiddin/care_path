"""
أدوات DRF مشتركة على مستوى المشروع:
- api_exception_handler: يحوّل IntegrityError (خرق قيد في قاعدة البيانات،
  غالباً بسبب طلبين متزامنين تجاوزا فحص الـ serializer) إلى 400 برسالة
  واضحة بدل 500.
- AtomicSaveMixin: يحفظ داخل transaction.atomic حتى يُلغى الـ savepoint
  عند IntegrityError وتبقى بقية الطلب (والاختبارات) سليمة.
"""

import logging

from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler

logger = logging.getLogger(__name__)

# كل قيد معروف: كلمات تظهر في رسالة الخطأ (اسم القيد في PostgreSQL، أو
# اسم العمود في SQLite) والرسالة التي تُرجع للعميل.
_CONSTRAINT_MESSAGES = (
    (
        ("one_active_case_per_patient", "cases_case.patient_id"),
        "هذا المريض لديه حالة نشطة بالفعل. أغلق حالته الحالية أولاً.",
    ),
    (
        ("one_case_per_device", "cases_case.device_id"),
        "هذا الجهاز مرتبط بحالة أخرى بالفعل (جهاز واحد لكل مريض).",
    ),
    (
        ("week_start_date",),
        "تم تسجيل تقرير هذا الأسبوع بالفعل.",
    ),
)


def _integrity_message(exc):
    text = str(exc)
    for needles, message in _CONSTRAINT_MESSAGES:
        if any(needle in text for needle in needles):
            return message
    return "تعارض مع بيانات موجودة. حدّث الصفحة وحاول مرة أخرى."


def api_exception_handler(exc, context):
    if isinstance(exc, IntegrityError):
        logger.warning("IntegrityError حُوّل إلى 400: %s", exc)
        return Response({"detail": _integrity_message(exc)}, status=status.HTTP_400_BAD_REQUEST)
    return exception_handler(exc, context)


class AtomicSaveMixin:
    def perform_create(self, serializer):
        with transaction.atomic():
            serializer.save()

    def perform_update(self, serializer):
        with transaction.atomic():
            serializer.save()
