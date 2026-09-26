from django.contrib import admin

from .models import Clinic, Device, DeviceType


@admin.register(Clinic)
class ClinicAdmin(admin.ModelAdmin):
    list_display = ("name", "responsible_engineer", "phone_number", "created_at")
    search_fields = ("name", "contact_person")


@admin.register(DeviceType)
class DeviceTypeAdmin(admin.ModelAdmin):
    list_display = ("name", "is_active", "updated_at")
    list_filter = ("is_active",)
    search_fields = ("name",)


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ("serial_number", "device_type", "clinic", "status", "updated_at")
    list_filter = ("status", "device_type", "clinic")
    search_fields = ("serial_number",)