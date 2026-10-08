from rest_framework import viewsets, permissions

from accounts.models import UserRole
from cases.scoping import scope_by_case
from .models import Feedback
from .serializers import FeedbackSerializer


class IsPatientOrDoctor(permissions.BasePermission):
    """التقييم مصدره المريض أو الطبيب فقط (FeedbackSource)."""

    message = "إضافة التقييمات مخصصة للمرضى والأطباء فقط."

    def has_permission(self, request, view):
        return getattr(request.user, "role", None) in {UserRole.PATIENT, UserRole.DOCTOR}


class IsFeedbackAuthorOrReadOnly(permissions.BasePermission):
    """يعدّل أو يحذف التقييمَ كاتبُه فقط — لا يمسح المريض تقييم الطبيب أو العكس."""

    message = "لا يمكنك تعديل أو حذف تقييم كتبه شخص آخر."

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.submitted_by_id == request.user.id


class FeedbackViewSet(viewsets.ModelViewSet):
    """
    - المريض: يستطيع إضافة تقييم على جلسات حالته فقط، ويرى تقييمات جلساته.
    - الطبيب: يرى تقييمات حالاته (من المريض ومنه هو)، ويستطيع إضافة تقييمه المهني.
    - المهندس: يرى كل التقييمات (لتقييم أداء الجهاز عبر الحالات)، دون إضافة.
    - أي دور آخر: لا شيء.
    - التعديل والحذف: لكاتب التقييم فقط.
    """

    serializer_class = FeedbackSerializer
    permission_classes = [permissions.IsAuthenticated, IsFeedbackAuthorOrReadOnly]

    def get_permissions(self):
        if self.action == "create":
            return [permissions.IsAuthenticated(), IsPatientOrDoctor()]
        return super().get_permissions()

    def get_queryset(self):
        return scope_by_case(
            Feedback.objects.all(), self.request.user, case_path="session__case"
        )

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context
