from rest_framework import viewsets, permissions

from .models import Feedback
from .serializers import FeedbackSerializer


class FeedbackViewSet(viewsets.ModelViewSet):
    """
    - المريض: يستطيع إضافة تقييم على جلسات حالته فقط، ويرى تقييماته فقط.
    - الطبيب: يرى تقييمات حالاته (من المريض ومنه هو)، ويستطيع إضافة تقييمه المهني.
    - المهندس: يرى كل التقييمات (لتقييم أداء الجهاز عبر الحالات).
    """

    serializer_class = FeedbackSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == "patient":
            return Feedback.objects.filter(session__case__patient=user)
        if user.role == "doctor":
            return Feedback.objects.filter(session__case__doctor=user)
        return Feedback.objects.all()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context