from rest_framework.permissions import BasePermission


class IsCaseParticipant(BasePermission):
    """يسمح فقط لمريض الحالة أو الطبيب المسؤول عنها بالوصول للمحادثة.
    عدّل أسماء الحقول (patient/doctor) إذا كانت مختلفة بموديل Case عندك."""

    def has_permission(self, request, view):
        case = view.get_case()
        user = request.user
        return case.patient_id == user.id or case.doctor_id == user.id