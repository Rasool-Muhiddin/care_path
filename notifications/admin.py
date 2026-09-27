from django.contrib import admin

from .models import DeviceToken


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "updated_at")
    list_filter = ("platform",)
    search_fields = ("user__username", "token")
    readonly_fields = ("created_at", "updated_at")
