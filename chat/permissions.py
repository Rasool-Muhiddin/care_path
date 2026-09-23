from rest_framework.permissions import BasePermission


class IsCaseParticipant(BasePermission):
    """يسمح لمريض الحالة وطبيبها والمهندس المسؤول بالوصول للقنوات المصرح بها.

    تصفية الرسائل نفسها تتم في الـ view: الطبيب لا يرى القناة التقنية.
    """

    def has_permission(self, request, view):
        case = view.get_case()
        user = request.user
        if case.patient_id == user.id or case.doctor_id == user.id:
            return True

        if getattr(user, 'role', None) != 'engineer':
            return False

        # المهندس المسؤول محفوظ على عيادة الجهاز. للحالات القديمة التي لم
        # يُربط جهازها/عيادتها بمهندس بعد، نسمح لفريق الدعم كي لا تضيع الرسالة.
        responsible_engineer_id = getattr(
            getattr(getattr(case, 'device', None), 'clinic', None),
            'responsible_engineer_id',
            None,
        )
        return responsible_engineer_id is None or responsible_engineer_id == user.id
