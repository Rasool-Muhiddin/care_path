from rest_framework import viewsets, permissions

from accounts.permissions import IsDoctorOrEngineer
from cases.scoping import scope_by_case
from config.drf import AtomicSaveMixin
from .models import TreatmentSession
from .serializers import TreatmentSessionSerializer


class TreatmentSessionViewSet(AtomicSaveMixin, viewsets.ModelViewSet):
    """
    - المريض: يرى جلسات حالاته الخاصة، ويستطيع إنشاء جلسة جديدة لحالته
      (تسجيل "تم إنهاء الجلسة")، لكن لا يستطيع تعديل أو حذف جلسة بعد إنشائها.
    - الطبيب: يرى ويسجّل ويعدّل جلسات حالاته فقط.
    - المهندس: يرى ويسجّل ويعدّل جلسات كل الحالات (لمتابعة الأداء الفني للجهاز).
    - أي دور آخر: لا شيء.

    فلترة اختيارية: ?case=<id> — تُستخدم من شاشة تفاصيل الجهاز عند المهندس
    لعرض جلسات حالة معيّنة فقط (لحساب حالة الالتزام بالجلسات).
    """

    serializer_class = TreatmentSessionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        # الإنشاء متاح لأي مستخدم مسجّل دخوله (المريض يسجّل جلسته بنفسه)؛
        # التحقق من أن الحالة ضمن نطاق المستخدم يتم داخل الـ Serializer.
        if self.action in ["update", "partial_update", "destroy"]:
            return [permissions.IsAuthenticated(), IsDoctorOrEngineer()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        queryset = scope_by_case(TreatmentSession.objects.all(), self.request.user)

        case_id = self.request.query_params.get("case")
        if case_id:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context
