from django.db import transaction
from django.db.models.signals import post_delete
from django.dispatch import receiver

from .models import ChatMessage


@receiver(post_delete, sender=ChatMessage)
def delete_voice_file(sender, instance, **kwargs):
    """حذف الرسالة (حذف حساب المريض، حذف حالة، الأدمن) يحذف ملفها الصوتي من
    القرص. يعمل مع الحذف المتسلسل (CASCADE) أيضاً. رسالة تبقى بمرسل NULL
    ("Deleted user") لا تُحذف فيبقى ملفها.

    بعد نجاح المعاملة فقط: لو تراجعت المعاملة تبقى الرسالة وملفها معاً.
    """
    if instance.audio:
        name, storage = instance.audio.name, instance.audio.storage
        transaction.on_commit(lambda: storage.delete(name))
