from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from cases.models import Case, CaseStatus
from cases.scoping import scoped_cases

from .models import TreatmentSession

DAILY_LIMIT_MESSAGE = "تم تسجيل الجلسة اليومية بالفعل اليوم. حاول مرة أخرى غداً."


def patient_logged_today(case) -> bool:
    """نعتمد على وقت السيرفر (created_at) وليس أي تاريخ يرسله العميل."""
    return TreatmentSession.objects.filter(
        case=case, created_at__date=timezone.localdate()
    ).exists()


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
            "created_at",
        ]
        # device يُؤخذ دائماً من جهاز الحالة نفسها (case.device)، وليس من الطلب
        read_only_fields = ["id", "device", "performed_by", "created_at"]

    def get_performed_by_name(self, obj):
        if not obj.performed_by:
            return None
        return obj.performed_by.get_full_name() or obj.performed_by.username

    def validate(self, attrs):
        """
        الإنشاء فقط (لا تعديل عبر الـ API)، والمستخدم مريض دائماً
        (TreatmentSessionViewSet.get_permissions):
        1. الحالة يجب أن تكون حالته (scoped_cases).
        2. لا جلسات على حالة مغلقة.
        3. لا يمكنه إرسال doctor_notes — هذا الحقل خاص بملاحظات الطبيب.
        4. جلسة واحدة في اليوم فقط (زر "إنهاء الجلسة اليومية"). يُعاد
           الفحص داخل قفل في create() لمنع طلبين متزامنين.
        """
        user = self.context["request"].user
        case = attrs.get("case")
        if case is None or not scoped_cases(user).filter(pk=case.pk).exists():
            raise serializers.ValidationError(
                {"case": "لا يمكنك تسجيل جلسة لحالة لا تخصك."}
            )
        if case.status == CaseStatus.CLOSED:
            raise serializers.ValidationError(
                {"case": "لا يمكن تسجيل جلسة على حالة مغلقة."}
            )
        if "doctor_notes" in self.initial_data:
            raise serializers.ValidationError(
                "لا يمكن للمريض تعديل الحقول التالية: doctor_notes"
            )
        if patient_logged_today(case):
            raise serializers.ValidationError(DAILY_LIMIT_MESSAGE)
        return attrs

    def create(self, validated_data):
        # نسجّل تلقائياً من نفّذ الجلسة، وعلى أي جهاز (جهاز الحالة نفسها).
        # وقت الجلسة هو وقت السيرفر. قفل صف الحالة يجعل طلبين متزامنين
        # يمرّان واحداً تلو الآخر، فيرى الثاني جلسة الأول.
        case = validated_data["case"]
        validated_data["performed_by"] = self.context["request"].user
        validated_data["device"] = case.device
        validated_data["session_date"] = timezone.now()
        with transaction.atomic():
            Case.objects.select_for_update().get(pk=case.pk)
            if patient_logged_today(case):
                raise serializers.ValidationError(DAILY_LIMIT_MESSAGE)
            return super().create(validated_data)
