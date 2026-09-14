from rest_framework import serializers

from .models import Feedback


class FeedbackSerializer(serializers.ModelSerializer):
    submitted_by_name = serializers.CharField(
        source="submitted_by.get_full_name", read_only=True
    )

    class Meta:
        model = Feedback
        fields = [
            "id",
            "session",
            "submitted_by",
            "submitted_by_name",
            "source",
            "rating",
            "comment",
            "created_at",
        ]
        read_only_fields = ["id", "submitted_by", "source", "created_at"]

    def create(self, validated_data):
        request = self.context["request"]
        validated_data["submitted_by"] = request.user
        # يُحدَّد المصدر تلقائياً حسب دور المستخدم، وليس مُدخلاً من الطلب
        validated_data["source"] = (
            "patient" if request.user.role == "patient" else "doctor"
        )
        return super().create(validated_data)