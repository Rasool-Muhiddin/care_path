from django.contrib.auth.models import AbstractUser
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

    # حقول اختيارية تُستخدم لاحقاً حسب الدور — يمكن نقلها لموديلات منفصلة
    # (DoctorProfile / EngineerProfile) عند تعقّد البيانات أكثر.
    specialty = models.CharField(
        max_length=100, blank=True, help_text="تخصص الطبيب (يُستخدم فقط عند role=doctor)"
    )

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