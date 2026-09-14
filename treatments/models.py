from django.conf import settings
from django.db import models

from cases.models import Case
from devices.models import Device


class TreatmentSession(models.Model):
    """
    جلسة علاجية واحدة باستخدام الجهاز ضمن حالة (Case) معيّنة.
    قد تُسجَّل الجلسة من قبل الطبيب أثناء الزيارة، أو من قبل المهندس
    عند إجراء صيانة/معايرة مرتبطة بجلسة علاج.
    """

    case = models.ForeignKey(Case, on_delete=models.CASCADE, related_name="sessions")
    device = models.ForeignKey(
        Device, on_delete=models.SET_NULL, null=True, related_name="sessions"
    )

    performed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="sessions_performed",
        help_text="الطبيب أو المهندس الذي نفّذ/أشرف على الجلسة",
    )

    session_date = models.DateTimeField()
    duration_minutes = models.PositiveIntegerField(null=True, blank=True)

    # إعدادات/معايرة الجهاز أثناء الجلسة — تُترك مرنة (JSON) لأن كل جهاز
    # قد يكون له معاملات مختلفة (شدة، تردد، مدة نبضة...) دون تعديل الموديل لاحقاً
    device_parameters = models.JSONField(
        default=dict, blank=True, help_text="إعدادات الجهاز أثناء هذه الجلسة"
    )

    doctor_notes = models.TextField(blank=True)
    patient_response = models.TextField(
        blank=True, help_text="استجابة/شكوى المريض المسجّلة خلال الجلسة"
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-session_date"]

    def __str__(self) -> str:
        return f"Session {self.session_date:%Y-%m-%d} - Case #{self.case_id}"