from django.contrib import admin

from .models import TreatmentSession


@admin.register(TreatmentSession)
class TreatmentSessionAdmin(admin.ModelAdmin):
    list_display = ("id", "case", "device", "performed_by", "session_date")
    list_filter = ("session_date",)
    search_fields = ("case__patient__username",)