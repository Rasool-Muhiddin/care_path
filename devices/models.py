import uuid

from django.conf import settings
from django.db import models


class Clinic(models.Model):
    """العيادة أو المركز الطبي الذي يستخدم الجهاز/الأجهزة."""

    name = models.CharField(max_length=150)
    address = models.CharField(max_length=255, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)
    contact_person = models.CharField(
        max_length=100, blank=True, help_text="اسم الشخص المسؤول في العيادة"
    )

    # المهندس المسؤول عن متابعة هذه العيادة من فريقكم
    responsible_engineer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="responsible_clinics",
        limit_choices_to={"role": "engineer"},
    )

    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return self.name


class DeviceType(models.Model):
    """
    نوع الجهاز العلاجي (مثال: النوع A، النوع B، النوع C).
    مصمم كجدول منفصل (وليس enum ثابت بالكود) حتى يمكن إضافة
    أنواع جديدة مستقبلاً من لوحة admin مباشرة بدون تعديل الكود.

    setup_schema: تعريف مرن (JSON) لشكل حقول "إعدادات الجهاز" الخاصة
    بهذا النوع. يبقى فارغًا {} إلى أن تُحدَّد الحقول التفصيلية لاحقًا؛
    عندها يمكن تعبئته دون أي تعديل على البنية (migration) من جديد.
    مثال مستقبلي:
        {
          "fields": [
            {"key": "intensity", "label": "شدة الجلسة", "type": "number"},
            {"key": "mode", "label": "نمط التشغيل", "type": "choice",
             "choices": ["A", "B"]}
          ]
        }
    """

    name = models.CharField(max_length=100, unique=True, help_text="اسم/رمز نوع الجهاز، مثال: النوع A")
    description = models.TextField(blank=True)
    setup_schema = models.JSONField(
        default=dict,
        blank=True,
        help_text="تعريف مرن لحقول إعداد هذا النوع، يُملأ لاحقًا بعد تحديد الحقول",
    )
    is_active = models.BooleanField(
        default=True, help_text="لإخفاء نوع قديم دون حذفه إذا توقف استخدامه"
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.name


class DeviceStatus(models.TextChoices):
    ACTIVE = "active", "Active"
    MAINTENANCE = "maintenance", "Under Maintenance"
    INACTIVE = "inactive", "Inactive"


class Device(models.Model):
    """
    جهاز علاجي فعلي (للشقيقة/الصرع) مُسلَّم لعيادة معيّنة.
    serial_number يجب أن يكون فريدًا لتتبع كل جهاز بدقة.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    serial_number = models.CharField(max_length=50, unique=True)

    # نوع الجهاز — يحدد شكل نافذة الإعدادات في التطبيق عند إنشاء Case
    device_type = models.ForeignKey(
        DeviceType,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="devices",
        help_text="نوع الجهاز، يحدد شكل حقول الإعداد الخاصة به",
    )

    clinic = models.ForeignKey(
        Clinic, on_delete=models.SET_NULL, null=True, blank=True, related_name="devices"
    )
    status = models.CharField(
        max_length=20, choices=DeviceStatus.choices, default=DeviceStatus.ACTIVE
    )

    installed_at = models.DateField(null=True, blank=True)
    last_maintenance_at = models.DateField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.serial_number