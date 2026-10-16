from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from accounts.models import UserRole

from .models import (
    ATTACK_DUPLICATE_WINDOW,
    ATTACK_FUTURE_TOLERANCE,
    ATTACK_MAX_DAYS_BACK,
    MAX_ATTACK_DURATION_SECONDS,
    AttackEvent,
    AttackLogConfirmation,
    Case,
    CaseStatus,
    DiagnosisType,
    DISEASE_TYPE_CHOICES_BY_DIAGNOSIS,
)


class CaseSerializer(serializers.ModelSerializer):
    patient_name = serializers.SerializerMethodField()
    doctor_name = serializers.SerializerMethodField()
    device_type_name = serializers.CharField(
        source="device.device_type.name", read_only=True
    )
    # للعرض في ملخص الحالة (الطبيب/المهندس): رقم الجهاز وعيادته
    device_serial_number = serializers.CharField(
        source="device.serial_number", read_only=True, default=None
    )
    clinic_name = serializers.CharField(source="device.clinic.name", read_only=True, default=None)
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
            "device_serial_number",
            "clinic_name",
            "device_setup_parameters",
            "diagnosis_type",
            "disease_type",
            "status",
            "monthly_episode_count",
            "episode_duration_minutes",
            "symptoms",
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

    def _sessions_count(self, obj):
        # sessions_count محسوبة مسبقاً في CaseViewSet.get_queryset (annotate)؛
        # الاستعلام المنفصل فقط لنسخة لم تمر عليه (مثل رد الإنشاء).
        count = getattr(obj, "sessions_count", None)
        return obj.sessions.count() if count is None else count

    def get_completed_sessions_count(self, obj):
        return self._sessions_count(obj)

    def get_remaining_sessions_count(self, obj):
        if obj.total_sessions_planned is None:
            return None
        remaining = obj.total_sessions_planned - self._sessions_count(obj)
        return max(remaining, 0)

    def validate(self, attrs):
        """
        المريض لا يصل هنا إطلاقاً (الحالة للقراءة فقط عنده — راجع
        CaseViewSet.get_permissions). القواعد هنا للطبيب والمهندس:

        1. لا يمكن نقل حالة موجودة إلى مريض آخر.
        2. الطبيب ينشئ الحالات لنفسه فقط ولا يغيّر طبيب الحالة.
        3. حالة واحدة غير مغلقة لكل مريض — عند الإنشاء، وعند إعادة فتح
           حالة مغلقة. لو صار للمريض حالتان نشطتان بجهازين مختلفين،
           تُسجَّل جلساته أحياناً على هذا الجهاز وأحياناً على ذاك.
        4. جهاز واحد لكل مريض: الجهاز المرتبط بحالة أخرى غير مغلقة لا
           يُقبل. الحالة المغلقة (جهاز مُرجَع) لا تحجز الجهاز، وإعادة فتحها
           تُرفض إن صار جهازها مرتبطاً بحالة نشطة أخرى.
        5. disease_type (إن أُرسل) يجب أن ينتمي فعلاً لأنواع تشخيص
           الحالة (diagnosis_type). راجع DISEASE_TYPE_CHOICES_BY_DIAGNOSIS.

        القواعد 3 و4 مدعومة أيضاً بقيود في قاعدة البيانات (Case.Meta)
        تلتقط الطلبات المتزامنة التي تتجاوز هذا الفحص.
        """
        request = self.context.get("request")
        user = getattr(request, "user", None)

        if self.instance is not None and "patient" in attrs:
            if attrs["patient"] != self.instance.patient:
                raise serializers.ValidationError(
                    {"patient": "لا يمكن نقل الحالة إلى مريض آخر."}
                )

        if getattr(user, "role", None) == UserRole.DOCTOR:
            current_doctor = self.instance.doctor if self.instance else user
            if "doctor" in attrs and attrs["doctor"] not in (None, current_doctor):
                raise serializers.ValidationError(
                    {"doctor": "لا يمكنك إسناد الحالة لطبيب آخر."}
                )
            if self.instance is None:
                attrs["doctor"] = user

        patient = attrs.get("patient", getattr(self.instance, "patient", None))
        status = attrs.get("status", getattr(self.instance, "status", CaseStatus.IN_TREATMENT))
        if patient is not None and status != CaseStatus.CLOSED:
            other_active = Case.objects.filter(patient=patient).exclude(status=CaseStatus.CLOSED)
            if self.instance is not None:
                other_active = other_active.exclude(pk=self.instance.pk)
            if other_active.exists():
                raise serializers.ValidationError(
                    "هذا المريض لديه حالة نشطة بالفعل. أغلق حالته "
                    "الحالية (status=closed) أولاً قبل إنشاء أو إعادة "
                    "فتح حالة أخرى له."
                )

        device = attrs.get("device", getattr(self.instance, "device", None))
        if device is not None and status != CaseStatus.CLOSED:
            taken = Case.objects.filter(device=device).exclude(status=CaseStatus.CLOSED)
            if self.instance is not None:
                taken = taken.exclude(pk=self.instance.pk)
            if taken.exists():
                reopening = (
                    self.instance is not None
                    and self.instance.status == CaseStatus.CLOSED
                    and "device" not in attrs
                )
                if reopening:
                    raise serializers.ValidationError(
                        {"device": (
                            f"لا يمكن إعادة فتح الحالة: جهازها ({device.serial_number}) "
                            "مرتبط الآن بحالة نشطة لمريض آخر. اختر جهازاً آخر "
                            "أو أعد فتحها بدون جهاز."
                        )}
                    )
                raise serializers.ValidationError(
                    {"device": "هذا الجهاز مرتبط بحالة نشطة أخرى (جهاز واحد لكل مريض)."}
                )

        disease_type = attrs.get("disease_type")
        if disease_type:
            diagnosis_type = attrs.get(
                "diagnosis_type",
                getattr(self.instance, "diagnosis_type", None),
            )
            allowed = dict(DISEASE_TYPE_CHOICES_BY_DIAGNOSIS.get(diagnosis_type, []))
            if disease_type not in allowed:
                raise serializers.ValidationError(
                    {
                        "disease_type": (
                            f'"{disease_type}" غير صالح لتشخيص "{diagnosis_type}".'
                        )
                    }
                )
        return attrs


class AttackEventSerializer(serializers.ModelSerializer):
    """
    نوبة واحدة — ينشئها المريض لحالته فقط. القواعد (كلها بالسيرفر):
    - الحالة تخص المريض وغير مغلقة.
    - occurred_at: ليس بالمستقبل (سماحية 5 دقائق)، ولا قبل (اليوم - 7
      أيام) بتوقيت بغداد، ولا قبل يوم إنشاء الحالة.
    - duration_seconds: 1 .. الحد الأقصى حسب التشخيص.
    - severity: إلزامي 1–10 للشقيقة، ومرفوض للصرع.
    - took_medication: إلزامي.
    - ضغطة مكررة (طلب مطابق خلال 60 ثانية) تُرفض — يُعاد الفحص داخل قفل
      صف الحالة في create() حتى لا يمر طلبان متزامنان.
    """

    class Meta:
        model = AttackEvent
        fields = [
            "id",
            "case",
            "occurred_at",
            "time_is_approximate",
            "duration_seconds",
            "severity",
            "took_medication",
            "created_at",
        ]
        read_only_fields = ["id", "created_at"]
        extra_kwargs = {"took_medication": {"required": True}}

    def validate(self, attrs):
        request = self.context["request"]
        case = attrs["case"]

        if case.patient_id != request.user.id:
            raise serializers.ValidationError({"case": "لا يمكنك تسجيل نوبة لحالة لا تخصك."})
        if case.status == CaseStatus.CLOSED:
            raise serializers.ValidationError({"case": "لا يمكن تسجيل نوبة على حالة مغلقة."})

        occurred_at = attrs["occurred_at"]
        now = timezone.now()
        if occurred_at > now + ATTACK_FUTURE_TOLERANCE:
            raise serializers.ValidationError({"occurred_at": "لا يمكن تسجيل نوبة بوقت في المستقبل."})
        occurred_day = timezone.localdate(occurred_at)
        if occurred_day < timezone.localdate(now) - timedelta(days=ATTACK_MAX_DAYS_BACK):
            raise serializers.ValidationError(
                {"occurred_at": f"يمكن تسجيل النوبات خلال آخر {ATTACK_MAX_DAYS_BACK} أيام فقط."}
            )
        if occurred_day < timezone.localdate(case.created_at):
            raise serializers.ValidationError({"occurred_at": "وقت النوبة قبل تاريخ تسجيل الحالة."})

        duration = attrs["duration_seconds"]
        max_duration = MAX_ATTACK_DURATION_SECONDS[case.diagnosis_type]
        if duration < 1 or duration > max_duration:
            raise serializers.ValidationError(
                {"duration_seconds": f"مدة النوبة يجب أن تكون بين 1 و {max_duration} ثانية."}
            )

        severity = attrs.get("severity")
        if case.diagnosis_type == DiagnosisType.MIGRAINE:
            if severity is None or not 1 <= severity <= 10:
                raise serializers.ValidationError({"severity": "شدة النوبة مطلوبة (من 1 إلى 10)."})
        elif severity is not None:
            raise serializers.ValidationError({"severity": "الشدة تُسجَّل لنوبات الشقيقة فقط."})
        return attrs

    def create(self, validated_data):
        case = validated_data["case"]
        with transaction.atomic():
            Case.objects.select_for_update().get(pk=case.pk)
            duplicate = AttackEvent.objects.filter(
                case=case,
                occurred_at=validated_data["occurred_at"],
                duration_seconds=validated_data["duration_seconds"],
                severity=validated_data.get("severity"),
                took_medication=validated_data["took_medication"],
                created_at__gte=timezone.now() - ATTACK_DUPLICATE_WINDOW,
            ).exists()
            if duplicate:
                raise serializers.ValidationError("تم تسجيل هذه النوبة للتو.")
            return super().create(validated_data)


class AttackLogConfirmationSerializer(serializers.ModelSerializer):
    """
    تأكيد "هل لديك نوبات لم تسجّلها؟" — المريض لحالته فقط، وتأكيد واحد
    لكل يوم (بتوقيت بغداد) لكل حالة.
    """

    class Meta:
        model = AttackLogConfirmation
        fields = ["id", "case", "had_unlogged", "confirmed_at"]
        read_only_fields = ["id", "confirmed_at"]
        extra_kwargs = {"had_unlogged": {"required": True}}

    def validate(self, attrs):
        request = self.context["request"]
        case = attrs["case"]
        if case.patient_id != request.user.id:
            raise serializers.ValidationError({"case": "لا يمكنك التأكيد لحالة لا تخصك."})
        if case.status == CaseStatus.CLOSED:
            raise serializers.ValidationError({"case": "الحالة مغلقة."})
        if AttackLogConfirmation.objects.filter(
            case=case, confirmed_at__date=timezone.localdate()
        ).exists():
            raise serializers.ValidationError("تم التأكيد اليوم بالفعل.")
        return attrs
