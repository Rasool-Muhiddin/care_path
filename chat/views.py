from functools import partial

from django.conf import settings
from django.http import FileResponse, Http404, HttpResponse
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.db.models import Count, F, IntegerField, OuterRef, Q, Subquery, Value
from django.db.models.functions import Coalesce
from accounts.models import UserRole
from accounts.permissions import IsEngineer
from cases.models import Case
from config.drf import int_query_param
from .models import ChatMessage
from .models import InquiryType
from .serializers import ChatMessageSerializer, EngineerInboxRowSerializer
from .permissions import (
    IsCaseParticipant,
    check_can_send,
    engineer_can_reply,
    engineer_owns_chat,
    messages_visible_to,
    responsible_engineer_of,
)
from .notifications import notify_in_background
from .voice import CONTENT_TYPE as VOICE_CONTENT_TYPE

# أول فتح للمحادثة (أو ?before_id=) يرجع آخر 50 رسالة فقط
CHAT_PAGE_SIZE = 50


class CaseMessagesView(generics.ListCreateAPIView):
    serializer_class = ChatMessageSerializer
    # IsAuthenticated صراحةً: تحديد permission_classes يستبدل الافتراضي، وبدونه
    # كان الطلب المجهول يجتاز IsCaseParticipant لحالة طبيبها null (None == None).
    permission_classes = [permissions.IsAuthenticated, IsCaseParticipant]
    # ترقيم خاص بالمحادثة (لا DEFAULT_PAGINATION_CLASS):
    # - بلا معاملات: آخر CHAT_PAGE_SIZE رسالة (أول فتح للشاشة).
    # - ?before_id=<id>: الـ CHAT_PAGE_SIZE رسالة الأقدم منها (التمرير للأعلى).
    # - ?after_id=<id>: كل الرسائل الأحدث منها (polling).
    # الرد دائماً قائمة مرتّبة من الأقدم للأحدث.
    # الـ header "X-Case-Status" يحمل حالة الحالة (in_treatment / closed) مع كل
    # polling، فتخفي الشاشة حقل الكتابة فور إغلاق الحالة دون طلب إضافي.
    pagination_class = None

    def get_case(self):
        if not hasattr(self, '_case'):
            # عيادة الجهاز ومهندسها تحدد حق المهندس في الرد (engineer_can_reply)
            self._case = get_object_or_404(
                Case.objects.select_related('device__clinic'), pk=self.kwargs['case_id']
            )
        return self._case

    def get_serializer_context(self):
        return {**super().get_serializer_context(), 'request': self.request}

    def get_queryset(self):
        # الطبيب لا يرى القناة التقنية، والطبية للمدير وحده من المهندسين
        queryset = messages_visible_to(self.request.user, self.get_case()).select_related('sender')

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
        # تحميل رسائل أقدم عند التمرير للأعلى
        before_id = int_query_param(self.request, 'before_id')
        if before_id is not None:
            queryset = queryset.filter(id__lt=before_id)
        return queryset

    def create(self, request, *args, **kwargs):
        # قواعد الإرسال (حالة مغلقة، حق رد المهندس) قبل التحقق من المحتوى، فلا
        # يُقرأ ملف صوتي ممن لا يحق له الإرسال. نفس المسار للنص والصوت.
        check_can_send(request.user, self.get_case())
        return super().create(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.save(case=self.get_case(), sender=self.request.user)
        # الإشعار بعد نجاح الحفظ فعلياً، وفي thread منفصل حتى لا ينتظر
        # الطلب (وعامل gunicorn) اتصال FCM بخوادم Google.
        transaction.on_commit(partial(notify_in_background, serializer.instance.pk))

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()
        if int_query_param(request, 'after_id') is not None:
            messages = list(queryset.order_by('id'))
        else:
            # آخر صفحة: نأخذ الأحدث ثم نعكسها لتبقى من الأقدم للأحدث
            messages = list(queryset.order_by('-id')[:CHAT_PAGE_SIZE])[::-1]
        data = self.get_serializer(messages, many=True).data

        # عند فتح الشاشة، علّم رسائل الطرف الآخر كمقروءة. المدير يطّلع على
        # القناة الطبية فقط، فلا نعلّمها مقروءة كي لا يختفي عدّاد الطبيب/المريض.
        # والمهندس غير المسؤول عن المحادثة (ومنه المدير في محادثة غيره) لا
        # يعلّم شيئاً كي يبقى العدّاد ظاهراً لدى المهندس المسؤول.
        unread = queryset.exclude(sender=request.user)
        if getattr(request.user, 'role', None) == UserRole.ENGINEER:
            if not engineer_owns_chat(request.user, self.get_case()):
                unread = unread.none()
            unread = unread.filter(inquiry_type=InquiryType.TECHNICAL)
        unread.update(is_read=True)
        return Response(data, headers={'X-Case-Status': self.get_case().status})


class UnreadCountView(APIView):
    def get(self, request):
        """عدد الرسائل غير المقروءة لكل حالات المستخدم (للعداد داخل التطبيق)"""
        user = request.user
        if getattr(user, 'role', None) == UserRole.ENGINEER:
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
        if getattr(user, 'role', None) == UserRole.DOCTOR:
            messages = messages.filter(inquiry_type=InquiryType.MEDICAL)
        elif getattr(user, 'role', None) == UserRole.ENGINEER:
            # القناة الطبية للاطلاع فقط عند المهندس، فلا تُحتسب كغير مقروءة له.
            # ورسائل المريض فقط، بنفس تعريف unread_count في صندوق الوارد.
            messages = messages.filter(inquiry_type=InquiryType.TECHNICAL, sender=F('case__patient'))
        # order_by() يلغي ترتيب الموديل (created_at) حتى لا يدخل في GROUP BY
        by_case = dict(
            messages.order_by().values('case').annotate(n=Count('id')).values_list('case', 'n')
        )
        return Response({'total_unread': sum(by_case.values()), 'by_case': by_case})


def _technical_messages_of_case():
    return ChatMessage.objects.filter(case=OuterRef('pk'), inquiry_type=InquiryType.TECHNICAL)


class EngineerInboxView(generics.ListAPIView):
    """صندوق رسائل المهندس: صف لكل محادثة تقنية (مريض ↔ مهندس) على حالة.

    كل المهندسين يرون كل المحادثات؛ can_reply يحدد هل يرد الطالب.
    ?mine=true: المحادثات التي يملك الطالب حق الرد فيها فقط (عيادته، أو
    بلا مهندس مسؤول). الترتيب: الأحدث رسالةً أولاً. استعلامان ثابتان لكل
    صفحة (العدّ + الصفحة) مهما زاد عدد المحادثات.
    """

    serializer_class = EngineerInboxRowSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]

    def get_queryset(self):
        technical = _technical_messages_of_case().order_by('-id')
        unread = (
            _technical_messages_of_case()
            .filter(is_read=False, sender=OuterRef('patient'))
            .order_by()
            .values('case')
            .annotate(n=Count('id'))
            .values('n')
        )
        queryset = (
            Case.objects.annotate(
                last_message_id=Subquery(technical.values('id')[:1]),
                last_message_text=Subquery(technical.values('text')[:1]),
                last_message_audio=Subquery(technical.values('audio')[:1]),
                last_message_at=Subquery(technical.values('created_at')[:1]),
                unread_count=Coalesce(Subquery(unread, output_field=IntegerField()), Value(0)),
            )
            .filter(last_message_id__isnull=False)
            .select_related('patient', 'device__clinic__responsible_engineer')
            .order_by('-last_message_id')
        )
        if self.request.query_params.get('mine') in ('true', '1'):
            # LEFT JOIN: يشمل الحالة بلا جهاز والجهاز بلا عيادة أيضاً
            queryset = queryset.filter(
                Q(device__clinic__responsible_engineer=self.request.user)
                | Q(device__clinic__responsible_engineer__isnull=True)
            )
        return queryset


class CaseReplyRightsView(APIView):
    """هل يستطيع المهندس الطالب الرد في القناة التقنية لهذه الحالة؟

    تستعملها شاشة المحادثة لإخفاء حقل الكتابة وعرض اسم المسؤول. الـ
    endpoint الفعلي للإرسال يفحص القاعدة نفسها ويرجع 403.
    """

    permission_classes = [permissions.IsAuthenticated, IsEngineer]

    def get(self, request, case_id):
        case = get_object_or_404(
            Case.objects.select_related('device__clinic__responsible_engineer'), pk=case_id
        )
        responsible = responsible_engineer_of(case)
        return Response({
            'case': case.pk,
            'can_reply': engineer_can_reply(request.user, case),
            'responsible_engineer': responsible.pk if responsible else None,
            'responsible_engineer_name': (
                (responsible.get_full_name() or responsible.username) if responsible else None
            ),
        })


class VoiceNoteView(APIView):
    """ملف الرسالة الصوتية — بنفس صلاحيات قراءة الرسالة نفسها.

    IsCaseParticipant على حالة الرسالة ثم messages_visible_to (نفس قاعدة
    CaseMessagesView). لا يعلّم الرسالة مقروءة. على السيرفر يسلّم الملف لـ
    nginx عبر X-Accel-Redirect (VOICE_NOTES_X_ACCEL_PREFIX)؛ محلياً يقرؤه Django.
    """

    permission_classes = [permissions.IsAuthenticated, IsCaseParticipant]

    def get_case(self):
        if not hasattr(self, '_case'):
            message = get_object_or_404(
                ChatMessage.objects.select_related('case__device__clinic'), pk=self.kwargs['message_id']
            )
            self._case = message.case
        return self._case

    def perform_content_negotiation(self, request, force=False):
        # الرد ملف صوتي وليس JSON: لا نرفض طلباً لأن Accept فيه audio/* فقط
        return super().perform_content_negotiation(request, force=True)

    def get(self, request, message_id):
        message = get_object_or_404(
            messages_visible_to(request.user, self.get_case()).exclude(audio=''), pk=message_id
        )
        prefix = settings.VOICE_NOTES_X_ACCEL_PREFIX
        if prefix:
            response = HttpResponse(content_type=VOICE_CONTENT_TYPE)
            response['X-Accel-Redirect'] = prefix.rstrip('/') + '/' + message.audio.name
        else:
            try:
                response = FileResponse(message.audio.open('rb'), content_type=VOICE_CONTENT_TYPE)
            except FileNotFoundError:
                raise Http404
        response['Content-Disposition'] = f'inline; filename="voice-{message.pk}.m4a"'
        # مراسلات طبية: لا تُخزَّن في أي cache وسيط
        response['Cache-Control'] = 'private, no-store'
        response['X-Content-Type-Options'] = 'nosniff'
        return response
