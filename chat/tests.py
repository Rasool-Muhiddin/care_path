from unittest import mock

from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import CareWorldMixin

from .models import ChatMessage, InquiryType


def messages_url(case):
    return f"/api/chat/cases/{case.pk}/messages/"


# لا نرسل إشعارات FCM حقيقية أثناء الاختبارات
@mock.patch("chat.views.notify_new_message")
class ChatPermissionTests(CareWorldMixin, APITestCase):
    def setUp(self):
        ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="medical",
                                   inquiry_type=InquiryType.MEDICAL)
        ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="technical",
                                   inquiry_type=InquiryType.TECHNICAL)

    def test_anonymous_gets_401_on_case_without_doctor(self, _notify):
        # H2: كان الطلب المجهول يجتاز الفحص لأن doctor_id == user.id == None
        client = self.client_for()
        self.assertEqual(client.get(messages_url(self.orphan_case)).status_code, status.HTTP_401_UNAUTHORIZED)
        response = client.post(messages_url(self.orphan_case), {"text": "hi"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(ChatMessage.objects.filter(case=self.orphan_case).exists())

    def test_other_patient_and_doctor_are_forbidden(self, _notify):
        for user in (self.patient_2, self.doctor_b):
            self.assertEqual(
                self.client_for(user).get(messages_url(self.case_1)).status_code,
                status.HTTP_403_FORBIDDEN,
            )

    def test_unknown_role_is_forbidden(self, _notify):
        response = self.client_for(self.no_role).get(messages_url(self.case_1))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_doctor_never_sees_technical_channel(self, _notify):
        response = self.client_for(self.doctor_a).get(
            messages_url(self.case_1), {"inquiry_type": "technical"}
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([m["text"] for m in response.data], [])

    def test_engineer_cannot_write_in_medical_channel(self, _notify):
        response = self.client_for(self.engineer).post(
            messages_url(self.case_1), {"text": "x", "inquiry_type": "medical"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_participant_can_send(self, notify):
        response = self.client_for(self.patient_1).post(
            messages_url(self.case_1), {"text": "hello", "inquiry_type": "medical"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        notify.assert_called_once()

    def test_unread_count_for_unknown_role_is_empty(self, _notify):
        response = self.client_for(self.no_role).get("/api/chat/unread-count/")
        self.assertEqual(response.data, {"total_unread": 0, "by_case": {}})

    def test_unread_count_doctor_only_counts_own_medical(self, _notify):
        response = self.client_for(self.doctor_a).get("/api/chat/unread-count/")
        self.assertEqual(response.data, {"total_unread": 1, "by_case": {self.case_1.pk: 1}})
