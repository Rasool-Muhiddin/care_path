from rest_framework import serializers

from cases.scoping import scope_by_case
from treatments.models import TreatmentSession

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
        extra_kwargs = {"rating": {"min_value": 1, "max_value": 5}}

    def validate(self, attrs):
        """
        - عند الإنشاء: الجلسة يجب أن تكون ضمن نطاق المستخدم (المريض على
          جلسات حالته فقط، والطبيب على جلسات حالاته فقط).
        - عند التعديل: لا يمكن نقل التقييم إلى جلسة أخرى.
        """
        if self.instance is not None:
            if "session" in attrs and attrs["session"] != self.instance.session:
                raise serializers.ValidationError(
                    {"session": "لا يمكن نقل التقييم إلى جلسة أخرى."}
                )
            return attrs

        user = self.context["request"].user
        session = attrs.get("session")
        allowed_sessions = scope_by_case(TreatmentSession.objects.all(), user)
        if session is None or not allowed_sessions.filter(pk=session.pk).exists():
            raise serializers.ValidationError(
                {"session": "لا يمكنك تقييم جلسة لا تخصك."}
            )
        return attrs

    def create(self, validated_data):
        request = self.context["request"]
        validated_data["submitted_by"] = request.user
        # يُحدَّد المصدر تلقائياً حسب دور المستخدم، وليس مُدخلاً من الطلب
        validated_data["source"] = (
            "patient" if request.user.role == "patient" else "doctor"
        )
        return super().create(validated_data)
