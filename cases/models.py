from django.conf import settings
from django.db import models

from devices.models import Device


class DiagnosisType(models.TextChoices):
    MIGRAINE = "migraine", "Migraine"
    EPILEPSY = "epilepsy", "Epilepsy"
    PARKINSON = "parkinson", "Parkinson's Disease"
    DEPRESSION = "depression", "Depression"
    OTHER = "other", "Other"


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
    status = models.CharField(
        max_length=25, choices=CaseStatus.choices, default=CaseStatus.NEW
    )

    # تفاصيل التشخيص السريري — تُستخدم حالياً مع الصرع والشقيقة
    # (تُترك فارغة لتشخيص "أخرى" أو أي حالة لا تنطبق عليها)
    weekly_episode_count = models.PositiveIntegerField(
        null=True, blank=True, help_text="عدد النوبات في الأسبوع"
    )
    episode_duration_minutes = models.PositiveIntegerField(
        null=True, blank=True, help_text="متوسط مدة النوبة بالدقائق"
    )
    current_medications = models.TextField(
        blank=True, help_text="الأدوية المستخدمة حالياً (نص حر)"
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