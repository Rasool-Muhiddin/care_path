from rest_framework import serializers

from .models import Clinic, Device, DeviceType


class ClinicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Clinic
        fields = "__all__"


class DeviceTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceType
        fields = [
            "id",
            "name",
            "description",
            "setup_schema",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class DeviceSerializer(serializers.ModelSerializer):
    clinic_name = serializers.CharField(source="clinic.name", read_only=True)
    device_type_name = serializers.CharField(source="device_type.name", read_only=True)
    # يُرسَل مع كل جهاز حتى تعرف واجهة الطبيب مباشرة أي حقول إعداد تعرض
    # عند اختيار هذا الجهاز، دون طلب إضافي منفصل لـ DeviceType
    device_type_setup_schema = serializers.JSONField(
        source="device_type.setup_schema", read_only=True
    )

    class Meta:
        model = Device
        fields = [
            "id",
            "serial_number",
            "model_name",
            "device_type",
            "device_type_name",
            "device_type_setup_schema",
            "clinic",
            "clinic_name",
            "status",
            "installed_at",
            "last_maintenance_at",
            "notes",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]