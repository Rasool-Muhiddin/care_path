from types import SimpleNamespace
from unittest import mock

from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import make_user

from .models import DeviceToken
from .services import WEB_PUSH_ICON, send_push_to_users


class WebTokenRegistrationTests(APITestCase):
    def setUp(self):
        self.user = make_user("patient", "patient")
        self.client.force_authenticate(self.user)

    def test_web_platform_is_accepted(self):
        response = self.client.post("/api/fcm-token/", {"token": "web-token-1", "platform": "web"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(DeviceToken.objects.get().platform, "web")

    def test_unknown_platform_is_rejected(self):
        response = self.client.post("/api/fcm-token/", {"token": "t", "platform": "windows"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class SendPushTests(APITestCase):
    def test_one_multicast_reaches_web_and_native_tokens_with_webpush_config(self):
        user = make_user("patient", "patient")
        DeviceToken.objects.create(user=user, token="android-1", platform="android")
        DeviceToken.objects.create(user=user, token="web-1", platform="web")
        sent = []

        def fake_send(message, app):
            sent.append(message)
            return SimpleNamespace(success_count=2, responses=[SimpleNamespace(success=True)] * 2)

        with mock.patch("notifications.services.get_firebase_app", return_value=object()), \
                mock.patch("notifications.services.messaging.send_each_for_multicast", fake_send):
            send_push_to_users([user], title="رسالة جديدة", body="لديك رسالة جديدة",
                               data={"type": "chat_message", "case_id": 5})

        message = sent[0]
        self.assertCountEqual(message.tokens, ["android-1", "web-1"])
        self.assertEqual(message.data, {"type": "chat_message", "case_id": "5"})
        self.assertEqual(message.webpush.headers["Urgency"], "high")
        self.assertEqual(message.webpush.notification.title, "رسالة جديدة")
        self.assertEqual(message.webpush.notification.icon, WEB_PUSH_ICON)
