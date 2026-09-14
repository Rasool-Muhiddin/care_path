from rest_framework import generics
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from cases.models import Case
from .models import ChatMessage
from .serializers import ChatMessageSerializer
from .permissions import IsCaseParticipant


class CaseMessagesView(generics.ListCreateAPIView):
    serializer_class = ChatMessageSerializer
    permission_classes = [IsCaseParticipant]

    def get_case(self):
        if not hasattr(self, '_case'):
            self._case = get_object_or_404(Case, pk=self.kwargs['case_id'])
        return self._case

    def get_serializer_context(self):
        return {**super().get_serializer_context(), 'request': self.request}

    def get_queryset(self):
        return ChatMessage.objects.filter(case=self.get_case())

    def perform_create(self, serializer):
        serializer.save(case=self.get_case(), sender=self.request.user)
        # TODO لاحقًا: notify_new_message(serializer.instance)  عند تفعيل push

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        # عند فتح الشاشة، علّم رسائل الطرف الآخر كمقروءة
        ChatMessage.objects.filter(case=self.get_case()).exclude(sender=request.user).update(is_read=True)
        return response


class UnreadCountView(APIView):
    def get(self, request):
        """عدد الرسائل غير المقروءة لكل حالات المستخدم (للعداد داخل التطبيق)"""
        user = request.user
        cases = (Case.objects.filter(patient=user) | Case.objects.filter(doctor=user)).distinct()
        by_case, total = {}, 0
        for case in cases:
            n = ChatMessage.objects.filter(case=case, is_read=False).exclude(sender=user).count()
            if n:
                by_case[case.id] = n
                total += n
        return Response({'total_unread': total, 'by_case': by_case})