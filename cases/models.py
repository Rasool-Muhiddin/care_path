from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from devices.models import Device


class DiagnosisType(models.TextChoices):
    MIGRAINE = "migraine", "Migraine"
    EPILEPSY = "epilepsy", "Epilepsy"


class EpilepsyType(models.TextChoices):
    """أنواع الصرع الفرعية — تظهر فقط عند اختيار تشخيص الصرع."""

    FOCAL = "focal", "Focal Epilepsy"
    GENERALIZED = "generalized", "Generalized Epilepsy"
    COMBINED = "combined", "Combined Generalized and Focal Epilepsy"
    UNKNOWN = "unknown", "Unknown Epilepsy"


class MigraineType(models.TextChoices):
    """أنواع الشقيقة الفرعية — تظهر فقط عند اختيار تشخيص الشقيقة."""

    WITHOUT_AURA = "without_aura", "Migraine without Aura"
    WITH_AURA = "with_aura", "Migraine with Aura"
    CHRONIC = "chronic", "Chronic Migraine"
    MENSTRUAL = "menstrual", "Menstrual Migraine"
    VESTIBULAR = "vestibular", "Vestibular Migraine"


# خريطة: كل تشخيص رئيسي له مجموعة "أنواعه الفرعية" الخاصة به فقط —
# تُستخدم بالـ Serializer (validate) للتأكد أن disease_type المُرسَل
# ينتمي فعلاً لتشخيص الحالة (Case.diagnosis_type)، حتى لا يُحفظ نوع
# فرعي يخص الصرع مع حالة تشخيصها شقيقة أو العكس.
DISEASE_TYPE_CHOICES_BY_DIAGNOSIS = {
    DiagnosisType.EPILEPSY: EpilepsyType.choices,
    DiagnosisType.MIGRAINE: MigraineType.choices,
}


def _all_disease_type_choices():
    """
    اتحاد كل الأنواع الفرعية عبر كل التشخيصات — تُستخدم فقط كـ choices
    لحقل disease_type على مستوى الموديل/الأدمن (قبول أي قيمة من أي
    تشخيص)، بينما التحقق الفعلي المرتبط بتشخيص الحالة بالذات يتم
    بالـ Serializer عبر DISEASE_TYPE_CHOICES_BY_DIAGNOSIS أعلاه.
    """
    merged = {}
    for choices in DISEASE_TYPE_CHOICES_BY_DIAGNOSIS.values():
        merged.update(dict(choices))
    return list(merged.items())


class CaseStatus(models.TextChoices):
    NEW = "new", "New"
    UNDER_EVALUATION = "under_evaluation", "Under Evaluation"
    IN_TREATMENT = "in_treatment", "In Treatment"
    CLOSED = "closed", "Closed"


class Case(models.Model):
    """
    الحالة المرضية التي تربط المريض بالطبيب (وبجهاز عند بدء العلاج).
    هذا هو الكيان المركزي الذي تدور حوله جلسات العلاج والـ Feedback.
    """

    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="cases_as_patient",
        limit_choices_to={"role": "patient"},
    )
    doctor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="cases_as_doctor",
        limit_choices_to={"role": "doctor"},
    )
    device = models.ForeignKey(
        Device,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="cases",
        help_text="الجهاز المخصص لعلاج هذه الحالة (قد يكون فارغاً قبل بدء العلاج)",
    )

    # القيم الفعلية لإعدادات الجهاز الخاصة بهذه الحالة، يحددها الطبيب عند
    # إنشاء/تعديل الحالة بناءً على device.device_type.setup_schema.
    # يبقى {} إلى أن تُحدَّد حقول setup_schema لكل نوع جهاز لاحقًا.
    device_setup_parameters = models.JSONField(
        default=dict,
        blank=True,
        help_text="إعدادات الجهاز الخاصة بهذه الحالة (حسب نوع الجهاز المختار)",
    )

    diagnosis_type = models.CharField(max_length=20, choices=DiagnosisType.choices)
    disease_type = models.CharField(
        max_length=20, choices=_all_disease_type_choices(), blank=True,
        help_text="نوع/تصنيف فرعي للمرض — يعتمد على diagnosis_type (انظر DISEASE_TYPE_CHOICES_BY_DIAGNOSIS)",
    )
    status = models.CharField(
        max_length=25, choices=CaseStatus.choices, default=CaseStatus.NEW
    )

    # تفاصيل التشخيص السريري — تُستخدم مع الصرع والشقيقة (التشخيصان
    # الوحيدان المتاحان حالياً، لذا تنطبق عملياً على كل حالة)
    monthly_episode_count = models.PositiveIntegerField(
        null=True, blank=True, help_text="عدد النوبات في الشهر"
    )
    episode_duration_minutes = models.PositiveIntegerField(
        null=True, blank=True, help_text="متوسط مدة النوبة بالدقائق (يُخزَّن دائماً بالدقائق حتى لو أدخله الطبيب بالساعات)"
    )
    symptoms = models.TextField(
        blank=True, help_text="الأعراض التي يعاني منها المريض (نص حر)"
    )
    current_medications = models.TextField(
        blank=True, help_text="الأدوية المستخدمة حالياً (نص حر)"
    )

    # العدد الإجمالي المخطط لجلسات العلاج لهذه الحالة — يحدده الطبيب.
    # يُترك فارغاً (None) إلى أن يُحدَّد؛ عندها تُحسب "الجلسات المتبقية"
    # للمريض كـ (total_sessions_planned - عدد الجلسات المسجَّلة فعلياً).
    total_sessions_planned = models.PositiveIntegerField(
        null=True, blank=True, help_text="العدد الإجمالي المخطط لجلسات العلاج"
    )

    # بيانات الكفيل/المرافق المسؤول عن شراء الجهاز — مطلوبة لأن الجهاز
    # يُباع للمريض بضمان كفيل يتحمل المسؤولية المالية/الإدارية
    guarantor_name = models.CharField(
        max_length=150, blank=True, help_text="Guarantor's full name"
    )
    guarantor_address = models.CharField(
        max_length=255, blank=True, help_text="Guarantor's address"
    )
    guarantor_phone_number = models.CharField(
        max_length=20, blank=True, help_text="Guarantor's phone number"
    )
    guarantor_email = models.EmailField(
        blank=True, help_text="Guarantor's email address"
    )

    initial_evaluation = models.TextField(
        blank=True, help_text="ملاحظات التقييم الأولي من الطبيب"
    )
    treatment_plan = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        # قواعد العمل على مستوى قاعدة البيانات (خط الدفاع الأخير ضد
        # الطلبات المتزامنة التي تتجاوز فحص الـ serializer):
        # - حالة واحدة غير مغلقة لكل مريض.
        # - الجهاز مرتبط بحالة واحدة غير مغلقة على الأكثر. عند إرجاع الجهاز
        #   تُغلق الحالة فيصبح الجهاز متاحاً لأي مريض آخر، وتبقى الحالة
        #   المغلقة (بجلساتها وتقييماتها وتقاريرها) مرتبطة به كسجل تاريخي.
        constraints = [
            models.UniqueConstraint(
                fields=["patient"],
                condition=~models.Q(status="closed"),
                name="one_active_case_per_patient",
            ),
            models.UniqueConstraint(
                fields=["device"],
                condition=models.Q(device__isnull=False) & ~models.Q(status="closed"),
                name="one_case_per_device",
            ),
        ]
        indexes = [
            # فحص "حالة نشطة واحدة" وقائمة حالات المريض
            models.Index(fields=["patient", "status"], name="case_patient_status_idx"),
        ]

    def __str__(self) -> str:
        return f"Case #{self.pk} - {self.patient} ({self.get_diagnosis_type_display()})"


# ---------------------------------------------------------------------------
# تسجيل النوبات عند حدوثها (بديل التقرير الأسبوعي الإلزامي)
# ---------------------------------------------------------------------------

# حدود المدة لكل تشخيص (بالثواني): الشقيقة بالساعات (فوق 72 ساعة حالة
# سريرية مختلفة)، والصرع بالثواني/الدقائق.
MAX_ATTACK_DURATION_SECONDS = {
    DiagnosisType.MIGRAINE: 72 * 3600,
    DiagnosisType.EPILEPSY: 60 * 60,
}
# أقدم يوم يُقبل تسجيل نوبة فيه: اليوم ناقص 7 أيام (بأيام بغداد الكاملة)
ATTACK_MAX_DAYS_BACK = 7
# سماحية فرق الساعة بين جهاز المريض والسيرفر
ATTACK_FUTURE_TOLERANCE = timedelta(minutes=5)
# المريض يقدر يحذف نوبة سجّلها بالخطأ خلال هذه المدة من التسجيل
ATTACK_DELETE_WINDOW = timedelta(hours=24)
# طلب مطابق تماماً لنوبة حُفظت قبل أقل من هذه المدة = ضغطة مكررة
ATTACK_DUPLICATE_WINDOW = timedelta(seconds=60)


class AttackEvent(models.Model):
    """
    نوبة واحدة يسجّلها المريض بنفسه (زر "تسجيل نوبة"). عدد النوبات لأي
    فترة = عدد السجلات فيها.

    - occurred_at: وقت بداية النوبة. إن اختار المريض جزءاً تقريبياً من
      اليوم (صباحاً/ظهراً/...) يُخزَّن وقت ممثِّل لذلك الجزء مع
      time_is_approximate=True.
    - severity: 1–10 للشقيقة فقط (إلزامي)، وفارغ دائماً للصرع.
    - التسجيل المتأخر يُحسب من الفرق بين created_at و occurred_at.
    """

    case = models.ForeignKey(Case, on_delete=models.CASCADE, related_name="attack_events")
    occurred_at = models.DateTimeField(help_text="وقت بداية النوبة")
    time_is_approximate = models.BooleanField(
        default=False, help_text="الوقت تقريبي (جزء من اليوم) وليس دقيقاً"
    )
    duration_seconds = models.PositiveIntegerField(help_text="مدة النوبة بالثواني")
    severity = models.PositiveSmallIntegerField(
        null=True, blank=True, help_text="شدة النوبة 1–10 (الشقيقة فقط)"
    )
    took_medication = models.BooleanField(help_text="هل أخذ المريض دواءً للنوبة")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-occurred_at", "-id"]
        indexes = [
            models.Index(fields=["case", "occurred_at"], name="attack_case_occurred_idx"),
        ]

    def __str__(self) -> str:
        return f"Attack on Case #{self.case_id} @ {self.occurred_at:%Y-%m-%d %H:%M}"


class AttackLogConfirmation(models.Model):
    """
    تأكيد أسبوعي خفيف (غير إلزامي) من المريض: "هل كانت لديك نوبات لم
    تسجّلها؟". التأكيد يغطي الأيام السبعة الكاملة التي تسبق يوم التأكيد
    (بتوقيت بغداد) — وهي بالضبط الأيام التي ما زال يُسمح بتسجيل نوبات
    فيها. had_unlogged=False: أكد عدم وجود نوبات غير مسجّلة.
    had_unlogged=True: أجاب "نعم" وسجّلها ثم أنهى.

    بهذا تستطيع شاشة الإحصائيات التفريق بين أسبوع بلا نوبات مؤكَّد
    وأسبوع بلا نوبات غير مؤكَّد.
    """

    case = models.ForeignKey(
        Case, on_delete=models.CASCADE, related_name="attack_log_confirmations"
    )
    had_unlogged = models.BooleanField()
    confirmed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-confirmed_at", "-id"]

    def __str__(self) -> str:
        return f"Attack-log confirmation for Case #{self.case_id} @ {self.confirmed_at:%Y-%m-%d}"
