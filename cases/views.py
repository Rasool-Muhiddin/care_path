from rest_framework import viewsets, permissions

from accounts.permissions import IsDoctorOrEngineer
from .models import Case
from .serializers import CaseSerializer


class CaseViewSet(viewsets.ModelViewSet):
    """
    - المريض: يرى فقط حالاته الخاصة (قراءة فقط عمليًا عبر فحص الـ Serializer).
    - الطبيب: يرى فقط الحالات المسندة إليه، ويستطيع تعديلها.
    - المهندس: يرى كل الحالات (لغرض ربطها بالأجهزة ومتابعة الاستخدام)، ويستطيع تعديل
      الحقول المتعلقة بالجهاز (device) لكن ليس الحقول الطبية البحتة عمليًا هذا يُترك
      كاتفاق فريق عمل موثّق، ويمكن تشديده أكثر بصلاحية منفصلة لاحقاً إن احتجتم.
    """

    serializer_class = CaseSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            # إنشاء حالة جديدة يكون من الطبيب أو المهندس فقط، وليس المريض مباشرة
            return [permissions.IsAuthenticated(), IsDoctorOrEngineer()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role == "patient":
            return Case.objects.filter(patient=user)
        if user.role == "doctor":
            return Case.objects.filter(doctor=user)
        # engineer
        return Case.objects.all()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context