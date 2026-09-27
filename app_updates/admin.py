from django.contrib import admin

from .models import AppVersion


@admin.register(AppVersion)
class AppVersionAdmin(admin.ModelAdmin):
    list_display = (
        "platform",
        "version_name",
        "version_code",
        "is_mandatory",
        "is_published",
        "created_at",
    )
    list_filter = ("platform", "is_published", "is_mandatory")
    search_fields = ("version_name", "release_notes")
    ordering = ("-version_code",)

    fieldsets = (
        (None, {"fields": ("platform", "version_name", "version_code", "release_notes")}),
        ("مصدر التحديث", {"fields": ("apk_file", "download_url")}),
        ("النشر", {"fields": ("is_mandatory", "is_published")}),
    )

    readonly_fields = ("created_at",)
