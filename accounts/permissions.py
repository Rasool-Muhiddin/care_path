"""
صلاحيات مبنية على الدور (Role-Based Permissions).

الفكرة: نفس الحماية التي نبنيها في Flutter (Router Guard) يجب تكرارها هنا
في السيرفر، لأن حماية الواجهة فقط غير كافية أبداً — أي شخص يمكنه استدعاء
الـ API مباشرة متجاوزاً التطبيق.

الاستخدام في أي View:
    permission_classes = [IsAuthenticated, IsDoctor]
"""

from rest_framework.permissions import BasePermission

from .models import UserRole


class IsPatient(BasePermission):
    message = "هذا الإجراء مخصص للمرضى فقط."

    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == UserRole.PATIENT
        )


class IsDoctor(BasePermission):
    message = "هذا الإجراء مخصص للأطباء فقط."

    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == UserRole.DOCTOR
        )


class IsEngineer(BasePermission):
    message = "هذا الإجراء مخصص لفريق المهندسين فقط."

    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == UserRole.ENGINEER
        )


class IsDoctorOrEngineer(BasePermission):
    """مفيدة للـ Endpoints التي يشترك فيها الطبيب والمهندس (مثل مراجعة حالة)."""

    message = "هذا الإجراء مخصص للأطباء أو فريق المهندسين."

    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role in {UserRole.DOCTOR, UserRole.ENGINEER}
        )


class IsOwnerOrStaff(BasePermission):
    """
    مثال object-level permission: المريض يرى بياناته الخاصة فقط،
    بينما الطبيب والمهندس يريان كل الحالات المرتبطة بهم.
    يُستخدم مع has_object_permission في الـ ViewSet.
    """

    def has_object_permission(self, request, view, obj) -> bool:
        user = request.user
        if user.role in {UserRole.DOCTOR, UserRole.ENGINEER}:
            return True
        # المريض: يجب أن يكون هو صاحب السجل (obj.patient == user)
        return getattr(obj, "patient_id", None) == user.id