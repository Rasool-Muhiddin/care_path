from django.db.models import Exists, OuterRef
from rest_framework import viewsets, permissions

from accounts.models import STAFF_ROLES
from accounts.permissions import IsEngineer
from config.drf import int_query_param
from .models import Clinic, Device, DeviceType
from .serializers import ClinicSerializer, DeviceSerializer, DeviceTypeSerializer


class ClinicViewSet(viewsets.ModelViewSet):
    """
    إدارة العيادات — مقتصرة بالكامل على المهندسين (فريقكم).
    لا يحتاج الطبيب أو المريض رؤية قائمة العيادات إطلاقاً.
    """

    queryset = Clinic.objects.order_by("name", "pk")
    serializer_class = ClinicSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]


class DeviceTypeViewSet(viewsets.ModelViewSet):
    """
    إدارة أنواع الأجهزة (Type A/B/C وأي نوع يُضاف لاحقاً) — مقتصرة على
    المهندسين. الطبيب يصل لبيانات النوع بشكل غير مباشر فقط عبر
    DeviceSerializer (device_type_name, device_type_setup_schema).
    """

    queryset = DeviceType.objects.order_by("name")
    serializer_class = DeviceTypeSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]


class DeviceViewSet(viewsets.ModelViewSet):
    """
    إدارة الأجهزة.
    - المهندس: صلاحية كاملة (إضافة/تعديل/حذف) على كل الأجهزة.
    - الطبيب: قراءة فقط، ويرى كل الأجهزة (وليس فقط أجهزة حالاته الحالية) —
      حتى يستطيع اختيار جهاز عند إنشاء أول حالة له.
    - المريض: لا يصل لهذا الـ Endpoint إطلاقاً (يرى جهازه فقط من خلال Case الخاص به).

    دعم فلترة "التوفر": الجهاز مع مريض واحد في كل وقت. يكون غير متاح ما
    دام مرتبطاً بحالة غير مغلقة؛ عند إرجاعه تُغلق الحالة فيعود متاحاً لأي
    مريض (الحالات المغلقة لا تُحتسب). مرّر ?available=true لإرجاع الأجهزة
    المتاحة فقط (تُستخدم في شاشة "New Case"). عند تعديل حالة موجودة، مرّر
    أيضاً ?exclude_case=<case_id> حتى يبقى الجهاز الحالي لتلك الحالة ضمن
    القائمة رغم كونه مرتبطاً بها.
    """

    serializer_class = DeviceSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            return [permissions.IsAuthenticated(), IsEngineer()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role not in STAFF_ROLES:
            # أي دور آخر (بما فيه المريض) لا يرى شيئاً من هنا
            return Device.objects.none()

        # استيراد محلي لتفادي أي استيراد دائري بين التطبيقين
        from cases.models import Case, CaseStatus

        # is_linked: هل الجهاز مع مريض حالياً (حالة غير مغلقة)؟ يُحسب داخل
        # نفس الاستعلام (EXISTS) بدل استعلام لكل جهاز في DeviceSerializer.
        active_cases = Case.objects.filter(device=OuterRef("pk")).exclude(status=CaseStatus.CLOSED)
        exclude_case_id = int_query_param(self.request, "exclude_case")
        if exclude_case_id is not None:
            active_cases = active_cases.exclude(pk=exclude_case_id)

        queryset = (
            Device.objects.select_related("clinic", "device_type")
            .annotate(is_linked=Exists(active_cases))
            .order_by("serial_number")
        )
        if self.request.query_params.get("available") == "true":
            queryset = queryset.filter(is_linked=False)
        return queryset