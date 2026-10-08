from functools import partial

from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.db.models import Count, Q
from accounts.models import UserRole
from cases.models import Case
from config.drf import int_query_param
from .models import ChatMessage
from .models import InquiryType
from .serializers import ChatMessageSerializer
from .permissions import IsCaseParticipant
from .notifications import notify_in_background


class CaseMessagesView(generics.ListCreateAPIView):
    serializer_class = ChatMessageSerializer
    # IsAuthenticated صراحةً: تحديد permission_classes يستبدل الافتراضي، وبدونه
    # كان الطلب المجهول يجتاز IsCaseParticipant لحالة طبيبها null (None == None).
    permission_classes = [permissions.IsAuthenticated, IsCaseParticipant]
    # بلا ترقيم صفحات: التطبيق يجلب الرسائل الجديدة فقط بـ ?after_id=<آخر id>
    # في كل polling، فالترقيم من الأقدم كان سيعيد الصفحة الأولى القديمة.
    pagination_class = None

    def get_case(self):
        if not hasattr(self, '_case'):
            self._case = get_object_or_404(Case, pk=self.kwargs['case_id'])
        return self._case

    def get_serializer_context(self):
        return {**super().get_serializer_context(), 'request': self.request}

    def get_queryset(self):
        queryset = ChatMessage.objects.filter(case=self.get_case()).select_related('sender')
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

        # polling تزايدي: الرسائل الأحدث من آخر رسالة لدى التطبيق فقط
        after_id = int_query_param(self.request, 'after_id')
        if after_id is not None:
            queryset = queryset.filter(id__gt=after_id)
        return queryset

    def perform_create(self, serializer):
        serializer.save(case=self.get_case(), sender=self.request.user)
        # الإشعار بعد نجاح الحفظ فعلياً، وفي thread منفصل حتى لا ينتظر
        # الطلب (وعامل gunicorn) اتصال FCM بخوادم Google.
        transaction.on_commit(partial(notify_in_background, serializer.instance.pk))

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        # عند فتح الشاشة، علّم رسائل الطرف الآخر كمقروءة. المهندس يطّلع على
        # القناة الطبية فقط، فلا نعلّمها مقروءة كي لا يختفي عدّاد الطبيب/المريض.
        unread = self.get_queryset().exclude(sender=request.user)
        if getattr(request.user, 'role', None) == 'engineer':
            unread = unread.filter(inquiry_type=InquiryType.TECHNICAL)
        unread.update(is_read=True)
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
        elif getattr(user, 'role', None) == UserRole.DOCTOR:
            cases = Case.objects.filter(doctor=user)
        elif getattr(user, 'role', None) == UserRole.PATIENT:
            cases = Case.objects.filter(patient=user)
        else:
            # الرفض كافتراض: أي دور آخر لا يملك محادثات
            cases = Case.objects.none()
        # استعلام واحد مجمّع لكل الحالات بدل استعلام لكل حالة
        messages = ChatMessage.objects.filter(case__in=cases, is_read=False).exclude(sender=user)
        if getattr(user, 'role', None) == 'doctor':
            messages = messages.filter(inquiry_type=InquiryType.MEDICAL)
        elif getattr(user, 'role', None) == 'engineer':
            # القناة الطبية للاطلاع فقط عند المهندس، فلا تُحتسب كغير مقروءة له.
            messages = messages.filter(inquiry_type=InquiryType.TECHNICAL)
        # order_by() يلغي ترتيب الموديل (created_at) حتى لا يدخل في GROUP BY
        by_case = dict(
            messages.order_by().values('case').annotate(n=Count('id')).values_list('case', 'n')
        )
        return Response({'total_unread': sum(by_case.values()), 'by_case': by_case})