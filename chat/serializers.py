from rest_framework import serializers
from .models import ChatMessage, InquiryType


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()
    sender_role = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = ['id', 'case', 'sender', 'sender_name', 'sender_role', 'inquiry_type', 'text', 'created_at', 'is_read', 'is_mine']
        read_only_fields = ['id', 'case', 'sender', 'created_at', 'is_read', 'sender_name', 'sender_role', 'is_mine']

    def get_sender_name(self, obj):
        return obj.sender.get_full_name() or obj.sender.username

    def get_sender_role(self, obj):
        return getattr(obj.sender, 'role', None)

    def get_is_mine(self, obj):
        request = self.context.get('request')
        return bool(request and obj.sender_id == request.user.id)

    def validate_inquiry_type(self, value):
        """المريض يختار نوع استفساره؛ الطبيب يكتب طبياً فقط.

        المهندس يستطيع الرد ضمن أي من القناتين حتى تصل إجابته إلى نفس
        المستلمين الذين استلموا سؤال المريض.
        """
        request = self.context.get('request')
        if not request:
            return value

        role = getattr(request.user, 'role', None)
        if role == 'doctor' and value != InquiryType.MEDICAL:
            raise serializers.ValidationError('الطبيب يستطيع الرد في الاستفسارات الطبية فقط.')
        if role == 'patient' and value not in InquiryType.values:
            raise serializers.ValidationError('نوع الاستفسار غير صالح.')
        return value
