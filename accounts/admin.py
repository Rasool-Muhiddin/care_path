from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    list_display = ("username", "email", "role", "is_manager", "first_name", "last_name", "is_staff")
    list_filter = ("role", "is_manager", "is_staff", "is_active")
    fieldsets = UserAdmin.fieldsets + (
        ("معلومات إضافية", {"fields": ("role", "is_manager", "phone_number", "specialty")}),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        ("معلومات إضافية", {"fields": ("role", "is_manager", "phone_number", "specialty")}),
    )