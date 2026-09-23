from django.db import models
from django.conf import settings
from cases.models import Case


class InquiryType(models.TextChoices):
    TECHNICAL = "technical", "Technical inquiry"
    MEDICAL = "medical", "Medical inquiry"


class ChatMessage(models.Model):
    case = models.ForeignKey(Case, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='sent_messages')
    inquiry_type = models.CharField(
        max_length=20,
        choices=InquiryType.choices,
        default=InquiryType.MEDICAL,
        help_text="القناة التي تنتمي إليها الرسالة؛ التقنية للمهندس، والطبية للطبيب والمهندس.",
    )
    text = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f"{self.sender} -> case #{self.case_id}: {self.text[:30]}"
