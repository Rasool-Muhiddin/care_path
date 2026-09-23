from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from devices.models import Device


class DiagnosisType(models.TextChoices):
    MIGRAINE = "migraine", "Migraine"
    EPILEPSY = "epilepsy", "Epilepsy"


class EpilepsyType(models.TextChoices):
    """
    أنواع الصرع الفرعية — تظهر فقط عند اختيار تشخيص الصرع.
    قيم مؤقتة (type1/type2/type3) إلى أن تُحدَّد الأنواع الفعلية لاحقاً.
    """

    TYPE1 = "type1", "Type 1"
    TYPE2 = "type2", "Type 2"
    TYPE3 = "type3", "Type 3"


class MigraineType(models.TextChoices):
    """
    أنواع الشقيقة الفرعية — تظهر فقط عند اختيار تشخيص الشقيقة.
    قيم مؤقتة (type1/type2/type3) إلى أن تُحدَّد الأنواع الفعلية لاحقاً.
    """

    TYPE1 = "type1", "Type 1"
    TYPE2 = "type2", "Type 2"
    TYPE3 = "type3", "Type 3"


# خريطة: كل تشخيص رئيسي له مجموعة "أنواعه الفرعية" الخاصة به فقط —
# تُستخدم بالـ Serializer (validate) للتأكد أن disease_type المُرسَل
# ينتمي فعلاً لتشخيص الحالة (Case.diagnosis_type)، حتى لا يُحفظ نوع
# فرعي يخص الصرع مع حالة تشخيصها شقيقة أو العكس.
# حالياً كل المجموعات متطابقة القيم (type1/2/3) لأن الأنواع الحقيقية
# لم تُحدَّد بعد — لاحقاً يكفي تعديل هذه الكلاسات فقط (EpilepsyType/
# MigraineType) دون أي تغيير بالكود من حولها.
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
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"Case #{self.pk} - {self.patient} ({self.get_diagnosis_type_display()})"


class CaseProgressNote(models.Model):
    """
    ملاحظة تطور دوريّة يكتبها الطبيب عند فحص المريض بعد عدد من الجلسات
    (مثال: "بعد 5 من أصل 15 جلسة، لاحظنا..."). سجل متعدد عبر الزمن —
    كل فحص يضيف إدخال جديد بدل استبدال النص السابق، حتى يقدر الطبيب
    يرجع يقارن كيف تطورت الحالة من فحص للثاني.

    sessions_completed_snapshot / total_sessions_planned_snapshot: لقطة
    تلقائية لعدد الجلسات وقت كتابة الملاحظة (وليس وقت القراءة لاحقاً)،
    حتى تبقى دقيقة تاريخياً حتى لو تغيّر total_sessions_planned بعدين.
    """

    case = models.ForeignKey(Case, on_delete=models.CASCADE, related_name="progress_notes")
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="case_progress_notes_written",
        help_text="الطبيب الذي كتب هذه الملاحظة",
    )

    note = models.TextField(help_text="نص حر يكتبه الطبيب لوصف التطور الملاحَظ")

    sessions_completed_snapshot = models.PositiveIntegerField(
        help_text="عدد الجلسات المكتملة وقت كتابة الملاحظة (لقطة تلقائية)"
    )
    total_sessions_planned_snapshot = models.PositiveIntegerField(
        null=True,
        blank=True,
        help_text="العدد الإجمالي المخطط وقت كتابة الملاحظة (لقطة تلقائية)",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"Progress note on Case #{self.case_id} @ {self.created_at:%Y-%m-%d}"


def _week_start(d):
    """يوم الاثنين من الأسبوع الذي يقع فيه التاريخ d."""
    return d - timedelta(days=d.weekday())


def pending_weekly_episode_week(case):
    """
    يرجّع تاريخ بداية (الاثنين) أقدم أسبوع لم يُسجَّل له تقرير نوبات
    أسبوعي بعد من طرف المريض، بدءاً من أسبوع إنشاء الحالة ولغاية آخر
    أسبوع اكتمل فعلياً (لا نطلب تقرير عن أسبوع لسا ما خلص). يرجّع None
    لو المريض مسجّل كل الأسابيع المستحقة، أو لو الحالة مغلقة.

    يُستخدم هذا لإجبار المريض على تسجيل عدد نوباته كل أسبوع (رسالة
    إلزامية بالواجهة تبقى تظهر لحد ما يجاوب، حتى لو أغلق التطبيق ورجع)،
    وبتراكم هذي التقارير الأسبوعية نقدر نبني سلسلة زمنية فعلية لعدد
    النوبات (بعكس Case.monthly_episode_count اللي هو رقم ثابت واحد فقط)
    تُستخدم لاحقاً بالتحليل الإحصائي (barplot: جلسات مقابل نوبات عبر
    الزمن، وتجميع كل 4 أسابيع = شهر واحد).
    """
    if case.status == CaseStatus.CLOSED:
        return None

    today = timezone.localdate()
    first_week_start = _week_start(case.created_at.date())
    reported_weeks = set(
        case.weekly_episode_logs.values_list("week_start_date", flat=True)
    )

    week = first_week_start
    while week + timedelta(days=7) <= today:
        if week not in reported_weeks:
            return week
        week += timedelta(days=7)
    return None


class WeeklyEpisodeLog(models.Model):
    """
    تقرير أسبوعي إلزامي يُدخله المريض بنفسه: كم نوبة/أزمة عانى منها
    خلال أسبوع معيّن (week_start_date = يوم الاثنين). إدخال واحد لكل
    أسبوع لكل حالة (unique_together)، ولا يمكن تعديله أو حذفه بعد
    الإرسال — سجل تاريخي ثابت.
    """

    case = models.ForeignKey(
        Case, on_delete=models.CASCADE, related_name="weekly_episode_logs"
    )
    week_start_date = models.DateField(
        help_text="تاريخ يوم الاثنين لبداية الأسبوع الذي يخص هذا التقرير"
    )
    episode_count = models.PositiveIntegerField(
        help_text="عدد النوبات التي أجاب بها المريض عن هذا الأسبوع"
    )
    submitted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["week_start_date"]
        unique_together = ("case", "week_start_date")

    def __str__(self) -> str:
        return f"Case #{self.case_id} — week of {self.week_start_date}: {self.episode_count}"