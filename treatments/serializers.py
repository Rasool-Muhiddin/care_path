from rest_framework import serializers

from .models import TreatmentSession


class TreatmentSessionSerializer(serializers.ModelSerializer):
    performed_by_name = serializers.SerializerMethodField()

    class Meta:
        model = TreatmentSession
        fields = [
            "id",
            "case",
            "device",
            "performed_by",
            "performed_by_name",
            "session_date",
            "duration_minutes",
            "device_parameters",
            "doctor_notes",
            "patient_response",
            "created_at",
        ]
        read_only_fields = ["id", "performed_by", "created_at"]

    def get_performed_by_name(self, obj):
        if not obj.performed_by:
            return None
        return obj.performed_by.get_full_name() or obj.performed_by.username

    def validate(self, attrs):
        """
        لو المستخدم مريض:
        1. يجب أن تكون الحالة (case) المُرسلة هي حالته الخاصة فقط — يمنع
           تسجيل جلسة نيابة عن مريض آخر.
        2. لا يمكنه تعديل doctor_notes — هذا الحقل خاص بملاحظات الطبيب.
        """
        request = self.context.get("request")
        if request and request.user.role == "patient":
            case = attrs.get("case") or getattr(self.instance, "case", None)
            if case and case.patient_id != request.user.id:
                raise serializers.ValidationError(
                    "لا يمكنك تسجيل جلسة لحالة لا تخصك."
                )
            forbidden = {"doctor_notes"} & set(self.initial_data.keys())
            if forbidden:
                raise serializers.ValidationError(
                    f"لا يمكن للمريض تعديل الحقول التالية: {', '.join(forbidden)}"
                )
        return attrs

    def create(self, validated_data):
        # نسجّل تلقائياً من نفّذ الجلسة من المستخدم المسجَّل دخوله
        request = self.context["request"]
        validated_data["performed_by"] = request.user
        return super().create(validated_data)