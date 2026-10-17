from django.db.models import Count
from django.utils import timezone
from rest_framework import viewsets, permissions
from rest_framework.exceptions import PermissionDenied
from rest_framework.throttling import ScopedRateThrottle

from accounts.models import UserRole
from accounts.permissions import (
    IsDoctorOrEngineerManager,
    IsEngineerManager,
    IsPatient,
    IsPatientOrEngineerManager,
)
from config.drf import AtomicSaveMixin, int_query_param, uuid_query_param
from .models import (
    ATTACK_DELETE_WINDOW,
    AttackEvent,
    AttackLogConfirmation,
    Case,
)
from .scoping import scope_by_case, scoped_cases
from .serializers import (
    AttackEventSerializer,
    AttackLogConfirmationSerializer,
    CaseSerializer,
)


class CaseViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    - المريض: قراءة حالاته الخاصة فقط — لا تعديل ولا حذف.
    - الطبيب: يرى الحالات المسندة إليه، ينشئ حالات لنفسه ويعدّلها، ولا يحذف.
    - المهندس: يرى كل الحالات (لمتابعة الأجهزة والاستخدام) — قراءة فقط.
    - مدير المهندسين: ينشئ ويعدّل كل الحالات، وهو الوحيد الذي يحذف — الحذف
      يمسح بالتسلسل كل الجلسات والنوبات والمحادثات المرتبطة.
    - أي دور آخر: لا شيء (راجع cases/scoping.py).

    فلترة اختيارية: ?device=<uuid> — تُستخدم من شاشة تفاصيل الجهاز عند
    المهندس لعرض الحالات المرتبطة بجهاز معيّن فقط.
    """

    serializer_class = CaseSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "destroy":
            return [permissions.IsAuthenticated(), IsEngineerManager()]
        if self.action in ["create", "update", "partial_update"]:
            return [permissions.IsAuthenticated(), IsDoctorOrEngineerManager()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        # كل ما يحتاجه CaseSerializer في عدد ثابت من الاستعلامات مهما كثرت
        # الحالات: الأسماء ونوع الجهاز بـ JOIN، وعدد الجلسات بـ annotate.
        queryset = (
            scoped_cases(self.request.user)
            .select_related(
                "patient", "doctor", "device__device_type", "device__clinic__responsible_engineer"
            )
            .annotate(sessions_count=Count("sessions", distinct=True))
            # صريحاً: Django يتجاهل Meta.ordering في استعلامات GROUP BY (annotate
            # Count)، فكانت القائمة المرقّمة بلا ترتيب ثابت
            .order_by(*Case._meta.ordering)
        )

        device_id = uuid_query_param(self.request, "device")
        if device_id:
            queryset = queryset.filter(device_id=device_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context


class AttackEventViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    نوبات المريض المسجّلة عند حدوثها.
    - المريض: ينشئ نوبات لحالته فقط، ويحذف نوبة سجّلها خلال 24 ساعة من
      تسجيلها (للأخطاء). لا تعديل — الخطأ يُحذف ويُسجَّل من جديد.
    - الطبيب: قراءة نوبات حالاته فقط.
    - المهندس: قراءة الكل.
    - مدير المهندسين: قراءة الكل، وحذف أي نوبة (للدعم الفني).

    إنشاء النوبات له حد خاص (throttle_scope="attack_create").
    فلترة اختيارية: ?case=<id>.
    """

    serializer_class = AttackEventSerializer
    http_method_names = ["get", "post", "delete", "head", "options"]
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            return [permissions.IsAuthenticated(), IsPatient()]
        if self.action == "destroy":
            return [permissions.IsAuthenticated(), IsPatientOrEngineerManager()]
        return [permissions.IsAuthenticated()]

    def get_throttles(self):
        throttles = super().get_throttles()
        if self.action == "create":
            self.throttle_scope = "attack_create"
            throttles.append(ScopedRateThrottle())
        return throttles

    def get_queryset(self):
        queryset = scope_by_case(AttackEvent.objects.all(), self.request.user)
        case_id = int_query_param(self.request, "case")
        if case_id is not None:
            queryset = queryset.filter(case_id=case_id)
        return queryset

    def perform_destroy(self, instance):
        if self.request.user.role == UserRole.PATIENT:
            if timezone.now() - instance.created_at > ATTACK_DELETE_WINDOW:
                raise PermissionDenied("يمكن حذف النوبة خلال 24 ساعة من تسجيلها فقط.")
        instance.delete()


class AttackLogConfirmationViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    التأكيدات الأسبوعية "لا نوبات غير مسجّلة". المريض ينشئ لحالته فقط
    (لا تعديل ولا حذف)، والطبيب/المهندس يقرؤون حسب نطاقهم.
    فلترة اختيارية: ?case=<id>.
    """

    serializer_class = AttackLogConfirmationSerializer
    http_method_names = ["get", "post", "head", "options"]
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            return [permissions.IsAuthenticated(), IsPatient()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        queryset = scope_by_case(AttackLogConfirmation.objects.all(), self.request.user)
        case_id = int_query_param(self.request, "case")
        if case_id is not None:
            queryset = queryset.filter(case_id=case_id)
        return queryset
