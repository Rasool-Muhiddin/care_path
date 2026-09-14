from rest_framework import viewsets, permissions

from accounts.permissions import IsDoctorOrEngineer
from .models import TreatmentSession
from .serializers import TreatmentSessionSerializer


class TreatmentSessionViewSet(viewsets.ModelViewSet):
    """
    - المريض: يرى جلسات حالاته الخاصة، ويستطيع إنشاء جلسة جديدة لحالته
      (تسجيل "تم إنهاء الجلسة")، لكن لا يستطيع تعديل أو حذف جلسة بعد إنشائها.
    - الطبيب: يرى ويسجّل ويعدّل جلسات حالاته فقط.
    - المهندس: يرى ويسجّل ويعدّل جلسات كل الحالات (لمتابعة الأداء الفني للجهاز).

    فلترة اختيارية: ?case=<id> — تُستخدم من شاشة تفاصيل الجهاز عند المهندس
    لعرض جلسات حالة معيّنة فقط (لحساب حالة الالتزام بالجلسات).
    """

    serializer_class = TreatmentSessionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        # الإنشاء متاح لأي مستخدم مسجّل دخوله (المريض يسجّل جلسته بنفسه)؛
        # التحقق من أن المريض ينشئ جلسة لحالته هو فقط يتم داخل الـ Serializer.
        if self.action in ["update", "partial_update", "destroy"]:
            return [permissions.IsAuthenticated(), IsDoctorOrEngineer()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role == "patient":
            queryset = TreatmentSession.objects.filter(case__patient=user)
        elif user.role == "doctor":
            queryset = TreatmentSession.objects.filter(case__doctor=user)
        else:
            queryset = TreatmentSession.objects.all()

        case_id = self.request.query_params.get("case")
        if case_id:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context