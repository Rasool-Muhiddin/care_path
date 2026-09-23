from django.contrib import admin

from .models import Case, WeeklyEpisodeLog


@admin.register(Case)
class CaseAdmin(admin.ModelAdmin):
    list_display = ("id", "patient", "doctor", "diagnosis_type", "status", "created_at")
    list_filter = ("status", "diagnosis_type")
    search_fields = ("patient__username", "doctor__username")


@admin.register(WeeklyEpisodeLog)
class WeeklyEpisodeLogAdmin(admin.ModelAdmin):
    list_display = ("id", "case", "week_start_date", "episode_count", "submitted_at")
    list_filter = ("week_start_date",)
    search_fields = ("case__patient__username",)