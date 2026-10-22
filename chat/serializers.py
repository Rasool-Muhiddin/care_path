from django.urls import reverse
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied
from accounts.models import UserRole
from cases.models import Case

from .models import ChatMessage, InquiryType
from .permissions import engineer_can_reply, responsible_engineer_of
from .voice import prepare_voice_note

# معاينة الرسالة الصوتية في صندوق الوارد (لا نص لها)
VOICE_PREVIEW = '🎤 رسالة صوتية'


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()
    sender_role = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()
    # "text" أو "voice". الصوت يُرفع multipart في الحقل audio ويُنزَّل من audio_url
    # (مسار نسبي، يتطلب نفس توكن الدخول).
    kind = serializers.SerializerMethodField()
    audio = serializers.FileField(write_only=True, required=False)
    audio_url = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = [
            'id', 'case', 'sender', 'sender_name', 'sender_role', 'inquiry_type', 'kind', 'text',
            'audio', 'audio_url', 'duration_seconds', 'created_at', 'is_read', 'is_mine',
        ]
        read_only_fields = [
            'id', 'case', 'sender', 'created_at', 'is_read', 'sender_name', 'sender_role', 'is_mine',
            'duration_seconds',
        ]

    DELETED_USER = 'Deleted user'

    def get_sender_name(self, obj):
        if obj.sender is None:
            return self.DELETED_USER
        return obj.sender.get_full_name() or obj.sender.username

    def get_sender_role(self, obj):
        return getattr(obj.sender, 'role', None)

    def get_is_mine(self, obj):
        request = self.context.get('request')
        return bool(request and obj.sender_id == request.user.id)

    def get_kind(self, obj):
        return 'voice' if obj.is_voice else 'text'

    def get_audio_url(self, obj):
        return reverse('chat-voice-note', args=[obj.pk]) if obj.is_voice else None

    def validate_inquiry_type(self, value):
        """المريض يختار نوع استفساره؛ الطبيب يكتب طبياً فقط.

        المهندس يقرأ القناة الطبية للاطلاع فقط ولا يكتب فيها (يُفحص في validate).
        """
        request = self.context.get('request')
        if not request:
            return value

        role = getattr(request.user, 'role', None)
        if role == UserRole.DOCTOR and value != InquiryType.MEDICAL:
            raise serializers.ValidationError('الطبيب يستطيع الرد في الاستفسارات الطبية فقط.')
        if role == UserRole.PATIENT and value not in InquiryType.values:
            raise serializers.ValidationError('نوع الاستفسار غير صالح.')
        return value

    def validate(self, attrs):
        """المهندس يرى القناة الطبية (كمدير) لكن لا يحق له الرد فيها.

        نفحص هنا وليس في validate_inquiry_type لأن الحقل غير مطلوب وقيمته
        الافتراضية طبية، فلا يعمل الفحص على الحقل إذا لم يُرسَل.
        """
        request = self.context.get('request')
        role = getattr(getattr(request, 'user', None), 'role', None)
        inquiry_type = attrs.get('inquiry_type', InquiryType.MEDICAL)
        if role == UserRole.ENGINEER and inquiry_type == InquiryType.MEDICAL:
            raise PermissionDenied('المهندس يستطيع قراءة القناة الطبية فقط ولا يمكنه الرد فيها.')

        # بعد فحص الصلاحية: لا نقرأ ملف من لا يحق له الإرسال أصلاً
        text = attrs.get('text', '')
        audio = attrs.get('audio')
        if bool(text) == bool(audio):
            raise serializers.ValidationError('الرسالة إما نص أو رسالة صوتية (واحد منهما فقط).')
        if audio:
            # يُخزَّن الملف المحوَّل (AAC m4a موحّد)، لا ما رُفع كما هو
            attrs['audio'], attrs['duration_seconds'] = prepare_voice_note(audio)
        return attrs

def _display_name(user):
    return (user.get_full_name() or user.username) if user else None


class EngineerInboxRowSerializer(serializers.ModelSerializer):
    """صف في صندوق رسائل المهندس — الحقول المشتقة تأتي من annotations
    و select_related في EngineerInboxView (لا استعلامات لكل صف)."""

    # نص المعاينة فقط؛ المحادثة كاملة عبر case-messages
    PREVIEW_LENGTH = 200

    case = serializers.IntegerField(source='pk', read_only=True)
    patient_name = serializers.SerializerMethodField()
    device_serial = serializers.CharField(source='device.serial_number', default=None, read_only=True)
    clinic_name = serializers.CharField(source='device.clinic.name', default=None, read_only=True)
    responsible_engineer = serializers.IntegerField(
        source='device.clinic.responsible_engineer_id', default=None, read_only=True
    )
    responsible_engineer_name = serializers.SerializerMethodField()
    case_status = serializers.CharField(source='status', read_only=True)
    last_message_text = serializers.SerializerMethodField()
    last_message_at = serializers.DateTimeField(read_only=True)
    unread_count = serializers.IntegerField(read_only=True)
    can_reply = serializers.SerializerMethodField()

    class Meta:
        model = Case
        fields = [
            'case', 'patient_name', 'device_serial', 'clinic_name', 'responsible_engineer',
            'responsible_engineer_name', 'case_status', 'last_message_text', 'last_message_at',
            'unread_count', 'can_reply',
        ]

    def get_patient_name(self, obj):
        return _display_name(obj.patient)

    def get_responsible_engineer_name(self, obj):
        return _display_name(responsible_engineer_of(obj))

    def get_last_message_text(self, obj):
        if obj.last_message_audio:
            return VOICE_PREVIEW
        return (obj.last_message_text or '')[: self.PREVIEW_LENGTH]

    def get_can_reply(self, obj):
        return engineer_can_reply(self.context['request'].user, obj)
