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
    # False إذا كان الجهاز مرتبطاً بحالة غير مغلقة (أي مع مريض حالياً)، بصرف
    # النظر عن حالة الجهاز نفسه (status). الحالات المغلقة (جهاز مُرجَع) لا
    # تُحتسب. يستثني حالة "exclude_case_id" الممرّرة من الـ view (لعرض جهاز
    # الحالة الحالية كـ "متاح" أثناء تعديلها)
    is_available = serializers.SerializerMethodField()

    def get_is_available(self, obj):
        # is_linked محسوبة في DeviceViewSet.get_queryset (مع احترام
        # ?exclude_case)؛ الاستعلام المنفصل فقط لنسخة لم تمر عليه (رد الإنشاء/التعديل).
        is_linked = getattr(obj, "is_linked", None)
        if is_linked is None:
            is_linked = obj.cases.exclude(status="closed").exists()
        return not is_linked

    class Meta:
        model = Device
        fields = [
            "id",
            "serial_number",
            "device_type",
            "device_type_name",
            "device_type_setup_schema",
            "clinic",
            "clinic_name",
            "status",
            "is_available",
            "installed_at",
            "last_maintenance_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]