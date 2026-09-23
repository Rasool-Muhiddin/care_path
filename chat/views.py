from rest_framework import generics
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from django.db.models import Q
from cases.models import Case
from .models import ChatMessage
from .models import InquiryType
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
        queryset = ChatMessage.objects.filter(case=self.get_case())
        user = self.request.user

        # لا يجوز للطبيب أن يطّلع على الاستفسارات التقنية أو ردودها.
        if getattr(user, 'role', None) == 'doctor':
            queryset = queryset.filter(inquiry_type=InquiryType.MEDICAL)

        # تعرض الواجهة قناة واحدة في كل مرة كي لا تختلط مراسلات الدعم
        # مع الاستفسارات الطبية لدى المريض أو المهندس.
        inquiry_type = self.request.query_params.get('inquiry_type')
        if inquiry_type:
            if inquiry_type not in InquiryType.values:
                return queryset.none()
            queryset = queryset.filter(inquiry_type=inquiry_type)
        return queryset

    def perform_create(self, serializer):
        serializer.save(case=self.get_case(), sender=self.request.user)
        # TODO لاحقًا: notify_new_message(serializer.instance)  عند تفعيل push

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        # عند فتح الشاشة، علّم رسائل الطرف الآخر كمقروءة
        self.get_queryset().exclude(sender=request.user).update(is_read=True)
        return response


class UnreadCountView(APIView):
    def get(self, request):
        """عدد الرسائل غير المقروءة لكل حالات المستخدم (للعداد داخل التطبيق)"""
        user = request.user
        if getattr(user, 'role', None) == 'engineer':
            # يتلقى المهندس الحالات المسندة إليه. نحافظ على ظهور الحالات
            # القديمة غير المسندة حتى لا تضيع رسائل الدعم إلى حين ربط العيادة.
            cases = Case.objects.filter(
                Q(device__clinic__responsible_engineer=user)
                | Q(device__isnull=True)
                | Q(device__clinic__isnull=True)
                | Q(device__clinic__responsible_engineer__isnull=True)
            ).distinct()
        else:
            cases = (Case.objects.filter(patient=user) | Case.objects.filter(doctor=user)).distinct()
        by_case, total = {}, 0
        for case in cases:
            messages = ChatMessage.objects.filter(case=case, is_read=False).exclude(sender=user)
            if getattr(user, 'role', None) == 'doctor':
                messages = messages.filter(inquiry_type=InquiryType.MEDICAL)
            n = messages.count()
            if n:
                by_case[case.id] = n
                total += n
        return Response({'total_unread': total, 'by_case': by_case})
