from django.db.models import Count
from rest_framework import viewsets, permissions

from accounts.models import UserRole
from accounts.permissions import IsDoctor, IsDoctorOrEngineer, IsEngineer, IsPatient
from config.drf import AtomicSaveMixin, int_query_param, uuid_query_param
from .models import Case, CaseProgressNote, WeeklyEpisodeLog
from .scoping import scope_by_case, scoped_cases
from .serializers import CaseProgressNoteSerializer, CaseSerializer, WeeklyEpisodeLogSerializer


class CaseViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    - المريض: قراءة حالاته الخاصة فقط — لا تعديل ولا حذف.
    - الطبيب: يرى الحالات المسندة إليه، ينشئ حالات لنفسه ويعدّلها، ولا يحذف.
    - المهندس: يرى ويعدّل كل الحالات (لربطها بالأجهزة ومتابعة الاستخدام)،
      وهو الوحيد الذي يحذف — الحذف يمسح بالتسلسل كل الجلسات والتقارير
      والمحادثات المرتبطة.
    - أي دور آخر: لا شيء (راجع cases/scoping.py).

    فلترة اختيارية: ?device=<uuid> — تُستخدم من شاشة تفاصيل الجهاز عند
    المهندس لعرض الحالات المرتبطة بجهاز معيّن فقط.
    """

    serializer_class = CaseSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "destroy":
            return [permissions.IsAuthenticated(), IsEngineer()]
        if self.action in ["create", "update", "partial_update"]:
            return [permissions.IsAuthenticated(), IsDoctorOrEngineer()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        # كل ما يحتاجه CaseSerializer في عدد ثابت من الاستعلامات مهما كثرت
        # الحالات: الأسماء ونوع الجهاز بـ JOIN، عدد الجلسات بـ annotate،
        # والتقارير الأسبوعية (للأسبوع المستحق) بـ prefetch.
        queryset = (
            scoped_cases(self.request.user)
            .select_related("patient", "doctor", "device__device_type")
            .annotate(sessions_count=Count("sessions", distinct=True))
            .prefetch_related("weekly_episode_logs")
        )

        device_id = uuid_query_param(self.request, "device")
        if device_id:
            queryset = queryset.filter(device_id=device_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context


class CaseProgressNoteViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    ملاحظات تطور الحالة عبر الزمن (سجل متعدد، وليس حقل واحد يُستبدل).
    - الطبيب: يرى ويكتب فقط لحالاته الخاصة.
    - المهندس: يرى الكل (قراءة فقط).
    - المريض وأي دور آخر: ممنوع بالكامل — لا رؤية ولا كتابة.

    فلترة اختيارية: ?case=<id> — لعرض ملاحظات حالة معيّنة فقط (هذا هو
    الاستخدام الطبيعي الوحيد تقريباً من شاشة تفاصيل الحالة عند الطبيب).
    """

    serializer_class = CaseProgressNoteSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            return [permissions.IsAuthenticated(), IsDoctor()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role == UserRole.PATIENT:
            return CaseProgressNote.objects.none()
        queryset = scope_by_case(CaseProgressNote.objects.all(), user)

        case_id = int_query_param(self.request, "case")
        if case_id is not None:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context


class WeeklyEpisodeLogViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    تقارير النوبات الأسبوعية.
    - المريض: يرسل (create) فقط تقاريره الخاصة عن الأسبوع المستحق —
      لا تعديل ولا حذف بعد الإرسال (سجل تاريخي ثابت).
    - الطبيب: يقرأ تقارير حالاته فقط (لبناء التحليل الإحصائي بالشارت).
    - المهندس: يقرأ الكل (للاتساق مع باقي الـ viewsets).

    إرسال نفس الأسبوع مرتين بالتزامن يصطدم بـ unique_together ويرجع 400
    (config.drf.api_exception_handler).

    فلترة اختيارية: ?case=<id> — لعرض تقارير حالة معيّنة فقط.
    """

    serializer_class = WeeklyEpisodeLogSerializer
    http_method_names = ["get", "post", "head", "options"]
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            return [permissions.IsAuthenticated(), IsPatient()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        queryset = scope_by_case(WeeklyEpisodeLog.objects.all(), self.request.user)

        case_id = int_query_param(self.request, "case")
        if case_id is not None:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context
