from django.contrib.auth.models import AbstractUser
from django.core.exceptions import ValidationError
from django.db import models


class UserRole(models.TextChoices):
    """
    الأدوار المسموح بها في النظام. لا تُكتب أسماء الأدوار كنصوص في أي مكان
    آخر — استعمل هذا الـ Enum دائماً.

    إضافة دور جديد (مثلاً "nurse"):
      1. أضفه هنا.
      2. cases/scoping.py → scope_by_case: ماذا يرى من الحالات وما يتفرع منها.
         بدون فرع صريح لا يرى شيئاً (الرفض كافتراض).
      3. accounts/permissions.py: صنف HasRole جديد إن احتاج صلاحيات خاصة.
      4. Flutter: UserRole في lib/core/permissions/user_role.dart (+ homeRoute
         ومسارات الراوتر). حراسة المسارات تُشتق من homeRoute تلقائياً.
    """
    PATIENT = "patient", "Patient"
    DOCTOR = "doctor", "Doctor"
    ENGINEER = "engineer", "Engineer"


class User(AbstractUser):
    """
    مستخدم مخصص يضيف حقل الدور (role) فوق نظام المصادقة الافتراضي في Django.
    يجب ضبط AUTH_USER_MODEL = "accounts.User" في settings.py قبل أول migration.
    """

    role = models.CharField(
        max_length=20,
        choices=UserRole.choices,
        help_text="يحدد نوع المستخدم ويتحكم بالشاشات والصلاحيات المتاحة له",
    )
    phone_number = models.CharField(max_length=20, blank=True)

    # مدير فريق المهندسين: صلاحيات كاملة (حذف الأجهزة، العيادات وأنواع
    # الأجهزة، تعديل الحالات، تسجيل الحسابات، القناة الطبية...). يُضبط من
    # Django admin فقط (غير قابل للكتابة عبر أي API)، وللمهندسين فقط.
    is_manager = models.BooleanField(
        default=False,
        help_text="مدير فريق المهندسين (صلاحيات كاملة). للمهندسين فقط — يُضبط من هنا فقط.",
    )

    # حقول اختيارية تُستخدم لاحقاً حسب الدور — يمكن نقلها لموديلات منفصلة
    # (DoctorProfile / EngineerProfile) عند تعقّد البيانات أكثر.
    specialty = models.CharField(
        max_length=100, blank=True, help_text="تخصص الطبيب (يُستخدم فقط عند role=doctor)"
    )

    # آخر طلب مصادَق من التطبيق (يُحدَّث مرة بالساعة كحد أقصى — راجع
    # accounts/authentication.py). last_login لا يكفي: لا يتغير عند تجديد
    # التوكن، والتطبيق نادراً ما يسجّل دخولاً جديداً.
    last_seen_at = models.DateTimeField(null=True, blank=True)
    # آخر تذكير push بتسجيل النوبات (send_attack_reminders) — تذكير واحد
    # كل 3 أيام على الأكثر.
    attack_reminder_sent_at = models.DateTimeField(null=True, blank=True)

    class Meta(AbstractUser.Meta):
        constraints = [
            models.CheckConstraint(
                condition=models.Q(is_manager=False) | models.Q(role="engineer"),
                name="manager_must_be_engineer",
            ),
        ]

    def clean(self):
        super().clean()
        if self.is_manager and self.role != UserRole.ENGINEER:
            raise ValidationError({"is_manager": "صلاحية المدير متاحة للمهندسين فقط."})

    def is_patient(self) -> bool:
        return self.role == UserRole.PATIENT

    def is_doctor(self) -> bool:
        return self.role == UserRole.DOCTOR

    def is_engineer(self) -> bool:
        return self.role == UserRole.ENGINEER

    def __str__(self) -> str:
        return f"{self.get_full_name() or self.username} ({self.get_role_display()})"


# الطاقم الطبي/الفني — يُستخدم في الصلاحيات والفلاتر بدل تكرار المجموعة
STAFF_ROLES = frozenset({UserRole.DOCTOR, UserRole.ENGINEER})