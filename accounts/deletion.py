"""
حذف الحساب من داخل التطبيق (مطلوب لمراجعة App Store / Google Play).

القواعد حسب الدور:
- المريض: حذف نهائي للحساب وكل بياناته — حالاته وما يتفرع منها (جلسات،
  نوبات، تأكيدات، محادثات) بالتسلسل من Case.patient (CASCADE). حذف الحالة
  يحرّر جهازها تلقائياً (لم تعد هناك حالة نشطة عليه).
- الطبيب: يُرفض إن كان لديه حالة غير مغلقة (يتواصل مع Tera لنقل مرضاه
  أولاً). غير ذلك يُحذف، وتبقى حالاته المغلقة بـ doctor = NULL.
- المهندس: يُحذف؛ العيادات التي هو مسؤولها تصبح بلا مسؤول (SET_NULL)،
  ورسائله تبقى بمرسل NULL ("Deleted user").
- مدير المهندسين وحساب superuser: لا يُحذفان من التطبيق (حتى لا يُقفل
  المالك خارج النظام) — من Django admin فقط.

في كل الحالات: تُبطَل كل refresh tokens للمستخدم وتُحذف توكنات FCM.
"""

from django.db import transaction
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

from accounts.models import UserRole
from accounts.permissions import is_engineer_manager
from cases.models import Case, CaseStatus
from chat.models import ChatMessage
from notifications.models import DeviceToken


class DeletionBlocked(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def deletion_block(user) -> DeletionBlocked | None:
    """سبب منع حذف الحساب من التطبيق، أو None إن كان الحذف مسموحاً."""
    if is_engineer_manager(user) or user.is_superuser:
        return DeletionBlocked(
            "manager_account",
            "لا يمكن حذف حساب المدير من التطبيق. يُحذف من لوحة Django admin فقط.",
        )
    if user.role == UserRole.DOCTOR and (
        Case.objects.filter(doctor=user).exclude(status=CaseStatus.CLOSED).exists()
    ):
        return DeletionBlocked(
            "doctor_has_active_cases",
            "لديك حالات غير مغلقة. تواصل مع Tera لنقل مرضاك إلى طبيب آخر قبل حذف حسابك.",
        )
    return None


def delete_account(user) -> None:
    """يحذف الحساب حسب القواعد أعلاه. يرفع DeletionBlocked إن كان ممنوعاً."""
    with transaction.atomic():
        # إعادة الفحص داخل المعاملة: حالة جديدة قد تُسند للطبيب بين الفحص والحذف
        type(user).objects.select_for_update().get(pk=user.pk)
        blocked = deletion_block(user)
        if blocked:
            raise blocked

        for token in OutstandingToken.objects.filter(user=user):
            BlacklistedToken.objects.get_or_create(token=token)
        DeviceToken.objects.filter(user=user).delete()

        if user.role == UserRole.PATIENT:
            # صريحاً (وليس فقط عبر CASCADE من user.delete) حتى تبقى القاعدة
            # واضحة: كل بيانات المريض تُحذف، ومنها أي رسالة أرسلها.
            Case.objects.filter(patient=user).delete()
            ChatMessage.objects.filter(sender=user).delete()

        user.delete()
