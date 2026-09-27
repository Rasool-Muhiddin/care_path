from django.db import models


class Platform(models.TextChoices):
    ANDROID = "android", "Android"
    IOS = "ios", "iOS"


class AppVersion(models.Model):
    """
    نسخة من تطبيق الموبايل يُصدرها الأدمن من لوحة تحكم Django.

    عند تفعيل is_published على نسخة جديدة بـ version_code أعلى من كل
    النسخ المنشورة الأخرى لنفس platform، سيراها التطبيق كـ "آخر تحديث
    متاح" في أول طلب لاحق لـ /api/app-version/latest/ ويعرض إشعار
    التحديث للمستخدم (بدون أي إشعار push — الفحص يحدث عند فتح التطبيق).
    """

    platform = models.CharField(
        max_length=10, choices=Platform.choices, default=Platform.ANDROID
    )
    version_name = models.CharField(
        max_length=30, help_text="مثال: 1.4.0 — نص وصفي يُعرض للمستخدم فقط"
    )
    version_code = models.PositiveIntegerField(
        help_text=(
            "رقم صحيح يزداد مع كل إصدار (يطابق versionCode في Android). "
            "هذا هو الرقم الذي تتم المقارنة عليه، وليس version_name."
        )
    )
    release_notes = models.TextField(
        blank=True, help_text="ماذا تغيّر في هذه النسخة — يُعرض للمستخدم في نافذة التحديث"
    )
    is_mandatory = models.BooleanField(
        default=False,
        help_text="إذا فُعّل: يمنع المستخدم من متابعة استخدام التطبيق قبل التحديث",
    )
    apk_file = models.FileField(
        upload_to="app_releases/",
        blank=True,
        null=True,
        help_text="ملف APK ليُحمَّل مباشرة من التطبيق (اختياري)",
    )
    download_url = models.URLField(
        blank=True,
        help_text="رابط خارجي للتحديث (Google Play مثلاً) — يُستخدم إن لم يُرفع ملف APK",
    )
    is_published = models.BooleanField(
        default=False,
        help_text="لا تظهر هذه النسخة للمستخدمين إلا بعد تفعيل هذا الخيار",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-version_code"]

    def __str__(self) -> str:
        return f"{self.get_platform_display()} v{self.version_name} ({self.version_code})"

    def download_link(self, request=None) -> str:
        """رابط التحميل الفعلي: ملف الـ APK إن وُجد، وإلا الرابط الخارجي."""
        if self.apk_file:
            url = self.apk_file.url
            return request.build_absolute_uri(url) if request is not None else url
        return self.download_url
