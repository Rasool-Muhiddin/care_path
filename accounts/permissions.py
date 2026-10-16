"""
صلاحيات مبنية على الدور (Role-Based Permissions).

الفكرة: نفس الحماية التي نبنيها في Flutter (Router Guard) يجب تكرارها هنا
في السيرفر، لأن حماية الواجهة فقط غير كافية أبداً — أي شخص يمكنه استدعاء
الـ API مباشرة متجاوزاً التطبيق.

الاستخدام في أي View:
    permission_classes = [IsAuthenticated, IsDoctor]

صلاحية لمجموعة أدوار جديدة = صنف من سطرين يرث HasRole ويحدد roles.
صلاحيات "المدير" (مهندس is_manager) تمر عبر is_engineer_manager().
ما يراه كل دور من البيانات نفسها يُحدَّد في cases/scoping.py.
"""

from rest_framework.permissions import BasePermission

from .models import STAFF_ROLES, UserRole


class HasRole(BasePermission):
    """يسمح فقط لمستخدم مسجّل دخوله دوره ضمن [roles]."""

    roles = frozenset()

    def has_permission(self, request, view) -> bool:
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and getattr(user, "role", None) in self.roles
        )


class IsPatient(HasRole):
    roles = frozenset({UserRole.PATIENT})
    message = "هذا الإجراء مخصص للمرضى فقط."


class IsDoctor(HasRole):
    roles = frozenset({UserRole.DOCTOR})
    message = "هذا الإجراء مخصص للأطباء فقط."


class IsEngineer(HasRole):
    roles = frozenset({UserRole.ENGINEER})
    message = "هذا الإجراء مخصص لفريق المهندسين فقط."


class IsDoctorOrEngineer(HasRole):
    """مفيدة للـ Endpoints التي يشترك فيها الطبيب والمهندس (مثل مراجعة حالة)."""

    roles = STAFF_ROLES
    message = "هذا الإجراء مخصص للأطباء أو فريق المهندسين."


def is_engineer_manager(user) -> bool:
    """مهندس بصلاحية مدير (User.is_manager، تُضبط من Django admin فقط)."""
    return bool(
        user
        and user.is_authenticated
        and getattr(user, "role", None) == UserRole.ENGINEER
        and getattr(user, "is_manager", False)
    )


class IsEngineerManager(BasePermission):
    message = "هذا الإجراء مخصص لمدير فريق المهندسين فقط."

    def has_permission(self, request, view) -> bool:
        return is_engineer_manager(request.user)


class IsDoctorOrEngineerManager(BasePermission):
    message = "هذا الإجراء مخصص للأطباء أو لمدير فريق المهندسين."

    def has_permission(self, request, view) -> bool:
        return IsDoctor().has_permission(request, view) or is_engineer_manager(request.user)


class IsPatientOrEngineerManager(BasePermission):
    message = "هذا الإجراء مخصص للمريض صاحب السجل أو لمدير فريق المهندسين."

    def has_permission(self, request, view) -> bool:
        return IsPatient().has_permission(request, view) or is_engineer_manager(request.user)
