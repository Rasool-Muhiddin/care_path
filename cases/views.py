from rest_framework import viewsets, permissions

from accounts.permissions import IsDoctorOrEngineer
from .models import Case, CaseProgressNote, WeeklyEpisodeLog
from .serializers import CaseProgressNoteSerializer, CaseSerializer, WeeklyEpisodeLogSerializer


class IsDoctorUser(permissions.BasePermission):
    """يسمح فقط للطبيب — يُستخدم لإضافة/تعديل/حذف ملاحظات التطور
    (المهندس يقرأها لكن لا يكتبها، والمريض ممنوع بالكامل)."""

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and getattr(request.user, "role", None) == "doctor"
        )


class IsPatientUser(permissions.BasePermission):
    """يسمح فقط للمريض — يُستخدم لتسجيل تقرير النوبات الأسبوعي (الطبيب
    والمهندس يقرآن فقط، لا يكتبان)."""

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and getattr(request.user, "role", None) == "patient"
        )


class CaseViewSet(viewsets.ModelViewSet):
    """
    - المريض: يرى فقط حالاته الخاصة (قراءة فقط عمليًا عبر فحص الـ Serializer).
    - الطبيب: يرى فقط الحالات المسندة إليه، ويستطيع تعديلها.
    - المهندس: يرى كل الحالات (لغرض ربطها بالأجهزة ومتابعة الاستخدام)، ويستطيع تعديل
      الحقول المتعلقة بالجهاز (device) لكن ليس الحقول الطبية البحتة عمليًا هذا يُترك
      كاتفاق فريق عمل موثّق، ويمكن تشديده أكثر بصلاحية منفصلة لاحقاً إن احتجتم.

    فلترة اختيارية: ?device=<uuid> — تُستخدم من شاشة تفاصيل الجهاز عند
    المهندس لعرض الحالات المرتبطة بجهاز معيّن فقط.
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
            queryset = Case.objects.filter(patient=user)
        elif user.role == "doctor":
            queryset = Case.objects.filter(doctor=user)
        else:
            # engineer
            queryset = Case.objects.all()

        device_id = self.request.query_params.get("device")
        if device_id:
            queryset = queryset.filter(device_id=device_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context


class CaseProgressNoteViewSet(viewsets.ModelViewSet):
    """
    ملاحظات تطور الحالة عبر الزمن (سجل متعدد، وليس حقل واحد يُستبدل).
    - الطبيب: يرى ويكتب فقط لحالاته الخاصة.
    - المهندس: يرى الكل (قراءة فقط).
    - المريض: ممنوع بالكامل — لا رؤية ولا كتابة.

    فلترة اختيارية: ?case=<id> — لعرض ملاحظات حالة معيّنة فقط (هذا هو
    الاستخدام الطبيعي الوحيد تقريباً من شاشة تفاصيل الحالة عند الطبيب).
    """

    serializer_class = CaseProgressNoteSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            return [permissions.IsAuthenticated(), IsDoctorUser()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role == "doctor":
            queryset = CaseProgressNote.objects.filter(case__doctor=user)
        elif user.role == "engineer":
            queryset = CaseProgressNote.objects.all()
        else:
            # المريض لا يرى شيئاً من هنا إطلاقاً
            return CaseProgressNote.objects.none()

        case_id = self.request.query_params.get("case")
        if case_id:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context

class WeeklyEpisodeLogViewSet(viewsets.ModelViewSet):
    """
    تقارير النوبات الأسبوعية.
    - المريض: يرسل (create) فقط تقاريره الخاصة عن الأسبوع المستحق —
      لا تعديل ولا حذف بعد الإرسال (سجل تاريخي ثابت).
    - الطبيب: يقرأ تقارير حالاته فقط (لبناء التحليل الإحصائي بالشارت).
    - المهندس: يقرأ الكل (للاتساق مع باقي الـ viewsets).

    فلترة اختيارية: ?case=<id> — لعرض تقارير حالة معيّنة فقط.
    """

    serializer_class = WeeklyEpisodeLogSerializer
    http_method_names = ["get", "post", "head", "options"]
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            return [permissions.IsAuthenticated(), IsPatientUser()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role == "patient":
            queryset = WeeklyEpisodeLog.objects.filter(case__patient=user)
        elif user.role == "doctor":
            queryset = WeeklyEpisodeLog.objects.filter(case__doctor=user)
        else:
            # engineer
            queryset = WeeklyEpisodeLog.objects.all()

        case_id = self.request.query_params.get("case")
        if case_id:
            queryset = queryset.filter(case_id=case_id)

        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context