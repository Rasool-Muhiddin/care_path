from django.urls import path
from .views import CaseMessagesView, UnreadCountView

urlpatterns = [
    path('cases/<int:case_id>/messages/', CaseMessagesView.as_view(), name='case-messages'),
    path('unread-count/', UnreadCountView.as_view(), name='chat-unread-count'),
]