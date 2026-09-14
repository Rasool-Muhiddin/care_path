from rest_framework import serializers
from .models import ChatMessage


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()
    sender_role = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = ['id', 'case', 'sender', 'sender_name', 'sender_role', 'text', 'created_at', 'is_read', 'is_mine']
        read_only_fields = ['id', 'case', 'sender', 'created_at', 'is_read', 'sender_name', 'sender_role', 'is_mine']

    def get_sender_name(self, obj):
        return obj.sender.get_full_name() or obj.sender.username

    def get_sender_role(self, obj):
        return getattr(obj.sender, 'role', None)

    def get_is_mine(self, obj):
        request = self.context.get('request')
        return bool(request and obj.sender_id == request.user.id)