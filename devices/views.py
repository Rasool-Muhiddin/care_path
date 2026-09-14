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
    - الطبيب: قراءة فقط، ويرى الأجهزة المرتبطة بحالاته فقط (وليس كل الأجهزة).
    - المريض: لا يصل لهذا الـ Endpoint إطلاقاً (يرى جهازه فقط من خلال Case الخاص به).
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
            return Device.objects.all()
        if user.role == "doctor":
            # الأجهزة المرتبطة بحالات هذا الطبيب فقط
            return Device.objects.filter(cases__doctor=user).distinct()
        # أي دور آخر (بما فيه المريض) لا يرى شيئاً من هنا
        return Device.objects.none()