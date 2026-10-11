from rest_framework.permissions import BasePermission

from accounts.models import UserRole


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


def engineer_can_reply(user, case) -> bool:
    """حق الرد في القناة التقنية: المهندس المسؤول عن عيادة الجهاز فقط.

    إن لم يوجد مهندس مسؤول (جهاز بلا عيادة أو عيادة بلا مهندس) يرد أي
    مهندس كي لا تضيع رسالة المريض.
    """
    if getattr(user, 'role', None) != UserRole.ENGINEER:
        return False
    responsible_id = responsible_engineer_id_of(case)
    return responsible_id is None or responsible_id == user.id


class IsCaseParticipant(BasePermission):
    """يسمح لمريض الحالة وطبيبها ولكل المهندسين بالوصول للمحادثة.

    كل المهندسين يقرؤون القناة التقنية (تخص الجهاز). تصفية الرسائل نفسها
    تتم في الـ view: الطبيب لا يرى القناة التقنية، والمهندس الذي لا يملك
    حق الرد لا يرى القناة الطبية. حق الرد يُفحص عند الإرسال.
    """

    def has_permission(self, request, view):
        case = view.get_case()
        user = request.user
        if case.patient_id == user.id or case.doctor_id == user.id:
            return True
        return getattr(user, 'role', None) == UserRole.ENGINEER
