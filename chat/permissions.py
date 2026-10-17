from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import BasePermission

from accounts.models import UserRole
from accounts.permissions import is_engineer_manager
from cases.models import CaseStatus

from .models import ChatMessage, InquiryType


def responsible_engineer_of(case):
    """المهندس المسؤول عن الحالة: حالة ← جهاز ← عيادة ← مهندسها المسؤول.

    يُشتق وقت الطلب ولا يُخزَّن على الحالة أو الجهاز، فتغيير مهندس العيادة
    ينقل حق الرد في كل أجهزتها فوراً. None إن لم يكن للجهاز عيادة أو
    لم يُحدَّد لعيادته مهندس.
    """
    device = getattr(case, 'device', None)
    clinic = getattr(device, 'clinic', None)
    return getattr(clinic, 'responsible_engineer', None)


def responsible_engineer_id_of(case):
    device = getattr(case, 'device', None)
    clinic = getattr(device, 'clinic', None)
    return getattr(clinic, 'responsible_engineer_id', None)


def engineer_owns_chat(user, case) -> bool:
    """المحادثة التقنية "تخص" المهندس المسؤول عن عيادة الجهاز.

    إن لم يوجد مهندس مسؤول (جهاز بلا عيادة أو عيادة بلا مهندس) تخص كل
    المهندسين كي لا تضيع رسالة المريض. صاحب المحادثة وحده يعلّمها مقروءة.
    """
    if getattr(user, 'role', None) != UserRole.ENGINEER:
        return False
    responsible_id = responsible_engineer_id_of(case)
    return responsible_id is None or responsible_id == user.id


def engineer_can_reply(user, case) -> bool:
    """حق الرد في القناة التقنية: صاحب المحادثة (engineer_owns_chat)، أو
    مدير المهندسين في أي محادثة."""
    return engineer_owns_chat(user, case) or is_engineer_manager(user)


def engineer_can_read_medical(user) -> bool:
    """القناة الطبية (مريض ↔ طبيب): للاطلاع فقط، ولمدير المهندسين وحده."""
    return is_engineer_manager(user)


def messages_visible_to(user, case):
    """رسائل الحالة التي يحق للمستخدم قراءتها — المصدر الوحيد لقاعدة القراءة،
    يستعمله عرض المحادثة وتنزيل ملف الرسالة الصوتية (بعد IsCaseParticipant).

    الطبيب لا يرى القناة التقنية. كل المهندسين يقرؤون القناة التقنية، أما
    القناة الطبية (مريض ↔ طبيب) فلمدير المهندسين وحده.
    """
    queryset = ChatMessage.objects.filter(case=case)
    role = getattr(user, 'role', None)
    if role == UserRole.DOCTOR:
        queryset = queryset.filter(inquiry_type=InquiryType.MEDICAL)
    if role == UserRole.ENGINEER and not engineer_can_read_medical(user):
        queryset = queryset.filter(inquiry_type=InquiryType.TECHNICAL)
    return queryset


def check_can_send(user, case) -> None:
    """قواعد الإرسال على مستوى الحالة، للنص والصوت معاً. يرفع PermissionDenied.

    - لا إرسال في حالة مغلقة.
    - في القناة التقنية يرد المهندس المسؤول عن عيادة الجهاز، والمدير في أي
      محادثة. (القناة الطبية يرفضها ChatMessageSerializer للمهندس أصلاً.)
    """
    if case.status == CaseStatus.CLOSED:
        raise PermissionDenied('هذه الحالة مغلقة، لا يمكن إرسال رسائل جديدة فيها.')
    if getattr(user, 'role', None) == UserRole.ENGINEER and not engineer_can_reply(user, case):
        responsible = responsible_engineer_of(case)
        name = responsible.get_full_name() or responsible.username
        raise PermissionDenied(
            f'لا يمكنك الرد في هذه المحادثة. الرد مخصص للمهندس المسؤول عن عيادة الجهاز: {name}.'
        )


class IsCaseParticipant(BasePermission):
    """يسمح لمريض الحالة وطبيبها ولكل المهندسين بالوصول للمحادثة.

    كل المهندسين يقرؤون القناة التقنية (تخص الجهاز). تصفية الرسائل نفسها
    تتم في الـ view: الطبيب لا يرى القناة التقنية، والقناة الطبية لا يراها
    من المهندسين إلا المدير. حق الرد يُفحص عند الإرسال.
    """

    def has_permission(self, request, view):
        case = view.get_case()
        user = request.user
        if case.patient_id == user.id or case.doctor_id == user.id:
            return True
        return getattr(user, 'role', None) == UserRole.ENGINEER
