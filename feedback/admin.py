from django.contrib import admin

from .models import Feedback


@admin.register(Feedback)
class FeedbackAdmin(admin.ModelAdmin):
    list_display = ("id", "session", "source", "submitted_by", "rating", "created_at")
    list_filter = ("source", "rating")