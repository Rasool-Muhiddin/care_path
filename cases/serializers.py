from rest_framework import serializers

from accounts.models import UserRole

from .models import (
    Case,
    CaseProgressNote,
    CaseStatus,
    DISEASE_TYPE_CHOICES_BY_DIAGNOSIS,
    WeeklyEpisodeLog,
    pending_weekly_episode_week,
)


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
    # أقدم أسبوع لسا ما سجّل له المريض تقرير نوبات (يوم اثنين، أو null
    # لو مسجّل كل شي) — تعتمد عليها شاشة المريض لعرض الرسالة الإلزامية.
    pending_weekly_episode_week = serializers.SerializerMethodField()

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
            "disease_type",
            "status",
            "monthly_episode_count",
            "episode_duration_minutes",
            "symptoms",
            "current_medications",
            "total_sessions_planned",
            "completed_sessions_count",
            "remaining_sessions_count",
            "pending_weekly_episode_week",
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

    def get_pending_weekly_episode_week(self, obj):
        week = pending_weekly_episode_week(obj)
        return week.isoformat() if week else None

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
        status = attrs.get("status", getattr(self.instance, "status", CaseStatus.NEW))
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


class CaseProgressNoteSerializer(serializers.ModelSerializer):
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = CaseProgressNote
        fields = [
            "id",
            "case",
            "author",
            "author_name",
            "note",
            "sessions_completed_snapshot",
            "total_sessions_planned_snapshot",
            "created_at",
        ]
        read_only_fields = [
            "id",
            "author",
            "sessions_completed_snapshot",
            "total_sessions_planned_snapshot",
            "created_at",
        ]

    def get_author_name(self, obj):
        if not obj.author:
            return None
        return obj.author.get_full_name() or obj.author.username

    def validate(self, attrs):
        """
        الطبيب يقدر يضيف ملاحظة فقط لحالة هو المسؤول عنها (case.doctor).
        المريض ممنوع بالكامل من هذا الـ endpoint (يُمنع أصلاً على مستوى
        الصلاحيات بالـ view، وهذا فحص إضافي احترازي).
        """
        request = self.context.get("request")
        case = attrs.get("case")
        if request and case is not None:
            if request.user.role == "doctor" and case.doctor_id != request.user.id:
                raise serializers.ValidationError(
                    "لا يمكنك إضافة ملاحظة تطور لحالة لا تخصك."
                )
            if request.user.role == "patient":
                raise serializers.ValidationError(
                    "لا يمكن للمريض إضافة ملاحظات تطور."
                )
        return attrs

    def create(self, validated_data):
        request = self.context["request"]
        case = validated_data["case"]
        validated_data["author"] = request.user
        # لقطة تلقائية لعدد الجلسات وقت الكتابة — الطبيب لا يدخلها يدوياً
        validated_data["sessions_completed_snapshot"] = case.sessions.count()
        validated_data["total_sessions_planned_snapshot"] = case.total_sessions_planned
        return super().create(validated_data)


class WeeklyEpisodeLogSerializer(serializers.ModelSerializer):
    """
    تقرير النوبات الأسبوعي — المريض يرسل فقط case و episode_count؛
    week_start_date تُحسب تلقائياً بالباكند (أقدم أسبوع مستحق حالياً)
    ولا تُقبل من الطلب أبداً، حتى لا يقدر يتلاعب بها أو يسجّل نفس
    الأسبوع مرتين أو أسبوعاً غير مستحق.
    """

    class Meta:
        model = WeeklyEpisodeLog
        fields = ["id", "case", "week_start_date", "episode_count", "submitted_at"]
        read_only_fields = ["id", "week_start_date", "submitted_at"]

    def validate(self, attrs):
        case = attrs.get("case")
        request = self.context.get("request")

        if request and case is not None:
            if request.user.role != "patient":
                raise serializers.ValidationError(
                    "فقط المريض يستطيع تسجيل تقرير النوبات الأسبوعي."
                )
            if case.patient_id != request.user.id:
                raise serializers.ValidationError(
                    "لا يمكنك تسجيل نوبات لحالة لا تخصك."
                )

        pending_week = pending_weekly_episode_week(case) if case is not None else None
        if pending_week is None:
            raise serializers.ValidationError(
                "لا يوجد تقرير أسبوعي مستحق حالياً لهذه الحالة."
            )
        attrs["week_start_date"] = pending_week
        return attrs