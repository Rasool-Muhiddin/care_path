from django.contrib import admin

from .models import AttackEvent, AttackLogConfirmation, Case


@admin.register(Case)
class CaseAdmin(admin.ModelAdmin):
    list_display = ("id", "patient", "doctor", "diagnosis_type", "status", "created_at")
    list_filter = ("status", "diagnosis_type")
    search_fields = ("patient__username", "doctor__username")


@admin.register(AttackEvent)
class AttackEventAdmin(admin.ModelAdmin):
    list_display = (
        "id", "case", "occurred_at", "time_is_approximate", "duration_seconds",
        "severity", "took_medication", "created_at",
    )
    list_filter = ("took_medication", "time_is_approximate", "case__diagnosis_type")
    search_fields = ("case__patient__username",)


@admin.register(AttackLogConfirmation)
class AttackLogConfirmationAdmin(admin.ModelAdmin):
    list_display = ("id", "case", "had_unlogged", "confirmed_at")
    list_filter = ("had_unlogged",)
    search_fields = ("case__patient__username",)
