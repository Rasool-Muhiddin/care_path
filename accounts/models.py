from django.contrib.auth.models import AbstractUser
from django.db import models


class UserRole(models.TextChoices):
    """
    الأدوار الثلاثة المسموح بها في النظام.
    أي دور جديد يُضاف مستقبلاً (مثلاً: Admin عام) يُضاف هنا فقط،
    وسينعكس تلقائياً في كل مكان يعتمد على هذا الـ Enum (صلاحيات، فلاتر، إلخ).
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
    is_active_account = models.BooleanField(
        default=True,
        help_text="لتعطيل حساب مستخدم (طبيب/مريض/مهندس) دون حذفه",
    )

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