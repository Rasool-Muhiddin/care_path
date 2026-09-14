from django.contrib import admin

from .models import Case


@admin.register(Case)
class CaseAdmin(admin.ModelAdmin):
    list_display = ("id", "patient", "doctor", "diagnosis_type", "status", "created_at")
    list_filter = ("status", "diagnosis_type")
    search_fields = ("patient__username", "doctor__username")