"""
أدوات DRF مشتركة على مستوى المشروع:
- api_exception_handler: يحوّل IntegrityError (خرق قيد في قاعدة البيانات،
  غالباً بسبب طلبين متزامنين تجاوزا فحص الـ serializer) إلى 400 برسالة
  واضحة بدل 500.
- AtomicSaveMixin: يحفظ داخل transaction.atomic حتى يُلغى الـ savepoint
  عند IntegrityError وتبقى بقية الطلب (والاختبارات) سليمة.
- DefaultPagination: ترقيم صفحات افتراضي لكل القوائم.
- int_query_param / uuid_query_param: قراءة معاملات الفلترة (?case=,
  ?device=, ...) مع إرجاع 400 عند قيمة غير صالحة بدل 500.
"""

import logging
import uuid

from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination
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


class DefaultPagination(PageNumberPagination):
    """
    50 عنصراً في الصفحة افتراضياً، والعميل يطلب حتى 200 بـ ?page_size=.
    تطبيق Flutter يتبع رابط "next" ليجمع القوائم التي يحتاجها كاملة
    (ApiClient.getAllPages)، فلا يُرجع أي طلب واحد أكثر من 200 عنصر.
    """

    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 200


def int_query_param(request, name):
    """يرجع قيمة ?name= كعدد صحيح، أو None إن لم تُرسل؛ 400 إن كانت غير صالحة."""
    raw = request.query_params.get(name)
    if raw in (None, ""):
        return None
    try:
        value = int(raw)
    except ValueError:
        raise ValidationError({name: "يجب أن يكون رقماً صحيحاً."})
    if value < 0:
        raise ValidationError({name: "يجب أن يكون رقماً صحيحاً."})
    return value


def uuid_query_param(request, name):
    """يرجع قيمة ?name= كـ UUID، أو None إن لم تُرسل؛ 400 إن كانت غير صالحة."""
    raw = request.query_params.get(name)
    if raw in (None, ""):
        return None
    try:
        return uuid.UUID(raw)
    except ValueError:
        raise ValidationError({name: "معرّف غير صالح."})
