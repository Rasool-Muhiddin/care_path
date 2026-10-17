from django.urls import path
from .views import CaseMessagesView, CaseReplyRightsView, EngineerInboxView, UnreadCountView, VoiceNoteView

urlpatterns = [
    path('cases/<int:case_id>/messages/', CaseMessagesView.as_view(), name='case-messages'),
    path('cases/<int:case_id>/reply-rights/', CaseReplyRightsView.as_view(), name='case-reply-rights'),
    path('messages/<int:message_id>/audio/', VoiceNoteView.as_view(), name='chat-voice-note'),
    path('unread-count/', UnreadCountView.as_view(), name='chat-unread-count'),
    path('engineer/inbox/', EngineerInboxView.as_view(), name='engineer-inbox'),
]
