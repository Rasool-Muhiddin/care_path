from django.db import models
from django.db.models import Q
from django.conf import settings
from cases.models import Case

from .voice import voice_storage, voice_upload_to


class InquiryType(models.TextChoices):
    TECHNICAL = "technical", "Technical inquiry"
    MEDICAL = "medical", "Medical inquiry"


class ChatMessage(models.Model):
    case = models.ForeignKey(Case, on_delete=models.CASCADE, related_name='messages')
    # SET_NULL: رسائل الطبيب/المهندس تبقى بعد حذف حسابه ("Deleted user").
    # رسائل المريض تُحذف مع حالاته (accounts/deletion.py).
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='sent_messages'
    )
    inquiry_type = models.CharField(
        max_length=20,
        choices=InquiryType.choices,
        default=InquiryType.MEDICAL,
        help_text="القناة التي تنتمي إليها الرسالة؛ التقنية للمهندس، والطبية للطبيب والمهندس.",
    )
    # الرسالة إما نص أو صوت، لا الاثنان ولا لا شيء (القيد chat_message_text_xor_voice)
    text = models.TextField(blank=True, default='')
    # ملف m4a (AAC) في تخزين خاص خارج MEDIA_ROOT؛ يُقدَّم عبر chat-voice-note فقط
    audio = models.FileField(upload_to=voice_upload_to, storage=voice_storage, blank=True, max_length=100)
    # مقروءة من الملف نفسه في الخادم (chat.voice.validate_voice_note)
    duration_seconds = models.PositiveSmallIntegerField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ['created_at', 'id']
        indexes = [
            # الـ polling وعدّاد غير المقروء: رسائل حالة معيّنة بقناة معيّنة وحالة قراءة
            models.Index(fields=['case', 'inquiry_type', 'is_read'], name='chat_case_type_read_idx'),
        ]
        constraints = [
            models.CheckConstraint(
                condition=(
                    (~Q(text='') & Q(audio='') & Q(duration_seconds__isnull=True))
                    | (Q(text='') & ~Q(audio='') & Q(duration_seconds__isnull=False))
                ),
                name='chat_message_text_xor_voice',
            ),
        ]

    @property
    def is_voice(self):
        return bool(self.audio)

    def __str__(self):
        body = f"[voice {self.duration_seconds}s]" if self.is_voice else self.text[:30]
        return f"{self.sender} -> case #{self.case_id}: {body}"
