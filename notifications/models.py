from django.conf import settings
from django.db import models


class Platform(models.TextChoices):
    ANDROID = "android", "Android"
    IOS = "ios", "iOS"


class DeviceToken(models.Model):
    """
    توكن FCM لجهاز واحد مرتبط بمستخدم. التوكن نفسه هو المفتاح الفريد
    (وليس user+token) لأن نفس الجهاز قد يُستخدم لاحقاً من مستخدم آخر
    (تسجيل خروج/دخول)، فعندها يُعاد ربط نفس التوكن بالمستخدم الجديد
    بدل ترك سجلين يشيران لنفس الجهاز الفعلي.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="device_tokens"
    )
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=10, choices=Platform.choices)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.user} — {self.platform} — {self.token[:16]}…"
