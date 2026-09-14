from django.conf import settings
from django.db import models

from treatments.models import TreatmentSession


class FeedbackSource(models.TextChoices):
    PATIENT = "patient", "Patient"
    DOCTOR = "doctor", "Doctor"


class Feedback(models.Model):
    """
    تقييم/ملاحظة على جلسة علاج محددة.
    يمكن أن تأتي من المريض (كيف شعر بعد الجلسة) أو من الطبيب (تقييم مهني للنتيجة).
    الفصل بين المصدرين (source) يسمح للواجهة بعرضهما بشكل مختلف.
    """

    session = models.ForeignKey(
        TreatmentSession, on_delete=models.CASCADE, related_name="feedback_entries"
    )
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True
    )
    source = models.CharField(max_length=10, choices=FeedbackSource.choices)

    rating = models.PositiveSmallIntegerField(
        null=True, blank=True, help_text="تقييم من 1 إلى 5 (اختياري)"
    )
    comment = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"Feedback ({self.source}) on session #{self.session_id}"