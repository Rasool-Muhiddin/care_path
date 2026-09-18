from rest_framework import viewsets, permissions

from accounts.permissions import IsEngineer
from .models import Clinic, Device, DeviceType
from .serializers import ClinicSerializer, DeviceSerializer, DeviceTypeSerializer


class ClinicViewSet(viewsets.ModelViewSet):
    """
    إدارة العيادات — مقتصرة بالكامل على المهندسين (فريقكم).
    لا يحتاج الطبيب أو المريض رؤية قائمة العيادات إطلاقاً.
    """

    queryset = Clinic.objects.all()
    serializer_class = ClinicSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]


class DeviceTypeViewSet(viewsets.ModelViewSet):
    """
    إدارة أنواع الأجهزة (Type A/B/C وأي نوع يُضاف لاحقاً) — مقتصرة على
    المهندسين. الطبيب يصل لبيانات النوع بشكل غير مباشر فقط عبر
    DeviceSerializer (device_type_name, device_type_setup_schema).
    """

    queryset = DeviceType.objects.all()
    serializer_class = DeviceTypeSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]


class DeviceViewSet(viewsets.ModelViewSet):
    """
    إدارة الأجهزة.
    - المهندس: صلاحية كاملة (إضافة/تعديل/حذف) على كل الأجهزة.
    - الطبيب: قراءة فقط، ويرى كل الأجهزة (وليس فقط أجهزة حالاته الحالية) —
      حتى يستطيع اختيار جهاز عند إنشاء أول حالة له.
    - المريض: لا يصل لهذا الـ Endpoint إطلاقاً (يرى جهازه فقط من خلال Case الخاص به).

    دعم فلترة "التوفر": كل جهاز يُباع لمريض واحد فقط، فبمجرد ربطه بأي Case
    يصبح غير متاح لأي Case آخر. مرّر ?available=true لإرجاع الأجهزة غير
    المرتبطة بأي حالة فقط (تُستخدم في شاشة "New Case"). عند تعديل حالة
    موجودة، مرّر أيضاً ?exclude_case=<case_id> حتى يبقى الجهاز الحالي لتلك
    الحالة ضمن القائمة رغم كونه مرتبطاً بها.
    """

    serializer_class = DeviceSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            return [permissions.IsAuthenticated(), IsEngineer()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        if user.role == "engineer":
            queryset = Device.objects.all()
        elif user.role == "doctor":
            queryset = Device.objects.all()
        else:
            # أي دور آخر (بما فيه المريض) لا يرى شيئاً من هنا
            return Device.objects.none()

        if self.request.query_params.get("available") == "true":
            # استيراد محلي لتفادي أي استيراد دائري بين التطبيقين
            from cases.models import Case

            linked_cases = Case.objects.exclude(device__isnull=True)

            exclude_case_id = self.request.query_params.get("exclude_case")
            if exclude_case_id:
                linked_cases = linked_cases.exclude(pk=exclude_case_id)

            linked_device_ids = linked_cases.values_list("device_id", flat=True)
            queryset = queryset.exclude(id__in=linked_device_ids)

        return queryset.distinct()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["exclude_case_id"] = self.request.query_params.get("exclude_case")
        return context