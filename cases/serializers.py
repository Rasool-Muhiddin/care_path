from rest_framework import serializers

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
        1. منع إنشاء أكثر من حالة (Case) نشطة واحدة لنفس المريض. المريض
           يجب أن يرتبط بجهاز واحد فقط، والجهاز مرتبط بالمريض عبر
           Case.device — فلو صار عنده حالتين نشطتين بجهازين مختلفين،
           تُسجَّل جلساته أحياناً على هذا الجهاز وأحياناً على ذاك حسب أي
           حالة يرجعها fetchMyCase() بالواجهة. هذا الفحص يمنع المشكلة من
           جذرها بدل معالجة أعراضها بالواجهة.
        2. المريض لا يجب أن يستطيع تعديل حقول الحالة السريرية (status,
           doctor, treatment_plan, initial_evaluation,
           device_setup_parameters, disease_type, monthly_episode_count,
           episode_duration_minutes, symptoms, current_medications,
           total_sessions_planned) حتى لو أرسلها ضمن الطلب. هذا فحص
           إضافي على مستوى الـ Serializer فوق فحص الصلاحيات في الـ View.
        3. disease_type (إن أُرسل) يجب أن ينتمي فعلاً لأنواع تشخيص
           الحالة (diagnosis_type) — نوع فرعي خاص بالصرع لا يُقبل مع
           حالة تشخيصها شقيقة والعكس. راجع DISEASE_TYPE_CHOICES_BY_DIAGNOSIS
           بـ models.py.
        """
        if self.instance is None:
            # فحص فقط عند الإنشاء (POST)، وليس عند التعديل (PATCH/PUT)
            patient = attrs.get("patient")
            if patient is not None:
                has_active_case = (
                    Case.objects.filter(patient=patient)
                    .exclude(status=CaseStatus.CLOSED)
                    .exists()
                )
                if has_active_case:
                    raise serializers.ValidationError(
                        "هذا المريض لديه حالة نشطة بالفعل. أغلق حالته "
                        "الحالية (status=closed) أولاً قبل إنشاء حالة "
                        "جديدة له."
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

        request = self.context.get("request")
        if request and request.user.role == "patient":
            clinical_fields = {
                "status",
                "doctor",
                "device",
                "device_setup_parameters",
                "disease_type",
                "monthly_episode_count",
                "episode_duration_minutes",
                "symptoms",
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