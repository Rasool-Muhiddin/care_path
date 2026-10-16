from rest_framework import mixins, permissions, viewsets

from accounts.permissions import IsPatient
from cases.scoping import scope_by_case
from config.drf import AtomicSaveMixin, int_query_param
from .models import TreatmentSession
from .serializers import TreatmentSessionSerializer


class TreatmentSessionViewSet(AtomicSaveMixin, mixins.CreateModelMixin, viewsets.ReadOnlyModelViewSet):
    """
    الجلسات عبر الـ API للقراءة فقط، والإنشاء للمريض وحده:
    - المريض: يرى جلسات حالاته، ويسجّل جلسته اليومية (زر "تم إنهاء
      الجلسة") — جلسة واحدة في اليوم.
    - الطبيب: يرى جلسات حالاته فقط.
    - المهندس: يرى جلسات كل الحالات.
    - أي دور آخر: لا شيء.
    لا تعديل ولا حذف عبر الـ API لأي دور (لا توجد مسارات PUT/PATCH/DELETE)؛
    التصحيحات تتم من لوحة Django admin.

    فلترة اختيارية: ?case=<id> — جلسات حالة معيّنة فقط.
    """

    serializer_class = TreatmentSessionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        # الإنشاء للمريض فقط؛ أن الحالة حالته يُتحقق منه في الـ Serializer.
        if self.action == "create":
            return [permissions.IsAuthenticated(), IsPatient()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        queryset = scope_by_case(
            TreatmentSession.objects.select_related("performed_by"), self.request.user
        )

        case_id = int_query_param(self.request, "case")
        if case_id is not None:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context
