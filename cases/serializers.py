from rest_framework import serializers

from .models import Case


class CaseSerializer(serializers.ModelSerializer):
    patient_name = serializers.SerializerMethodField()
    doctor_name = serializers.SerializerMethodField()
    device_type_name = serializers.CharField(
        source="device.device_type.name", read_only=True
    )
    # الجلسات المكتملة فعلياً (تُحسب من TreatmentSession المرتبطة بالحالة)،
    # والجلسات المتبقية إذا كان total_sessions_planned محدداً.
    completed_sessions_count = serializers.SerializerMethodField()
    remaining_sessions_count = serializers.SerializerMethodField()

    class Meta:
        model = Case
        fields = [
            "id",
            "patient",
            "patient_name",
            "doctor",
            "doctor_name",
            "device",
            "device_type_name",
            "device_setup_parameters",
            "diagnosis_type",
            "status",
            "weekly_episode_count",
            "episode_duration_minutes",
            "current_medications",
            "total_sessions_planned",
            "completed_sessions_count",
            "remaining_sessions_count",
            "guarantor_name",
            "guarantor_address",
            "guarantor_phone_number",
            "guarantor_email",
            "initial_evaluation",
            "treatment_plan",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_patient_name(self, obj):
        # fallback لليوزرنيم لو first_name/last_name فاضيين
        return obj.patient.get_full_name() or obj.patient.username

    def get_doctor_name(self, obj):
        if not obj.doctor:
            return None
        return obj.doctor.get_full_name() or obj.doctor.username

    def get_completed_sessions_count(self, obj):
        return obj.sessions.count()

    def get_remaining_sessions_count(self, obj):
        if obj.total_sessions_planned is None:
            return None
        remaining = obj.total_sessions_planned - obj.sessions.count()
        return max(remaining, 0)

    def validate(self, attrs):
        """
        المريض لا يجب أن يستطيع تعديل حقول الحالة السريرية (status, doctor,
        treatment_plan, initial_evaluation, device_setup_parameters,
        weekly_episode_count, episode_duration_minutes,
        current_medications, total_sessions_planned) حتى لو أرسلها ضمن
        الطلب. هذا فحص إضافي على مستوى الـ Serializer فوق فحص الصلاحيات
        في الـ View.
        """
        request = self.context.get("request")
        if request and request.user.role == "patient":
            clinical_fields = {
                "status",
                "doctor",
                "device",
                "device_setup_parameters",
                "weekly_episode_count",
                "episode_duration_minutes",
                "current_medications",
                "total_sessions_planned",
                "guarantor_name",
                "guarantor_address",
                "guarantor_phone_number",
                "guarantor_email",
                "treatment_plan",
                "initial_evaluation",
            }
            forbidden = clinical_fields & set(self.initial_data.keys())
            if forbidden:
                raise serializers.ValidationError(
                    f"لا يمكن للمريض تعديل الحقول التالية: {', '.join(forbidden)}"
                )
        return attrs