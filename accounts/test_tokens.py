from django.test import override_settings
from rest_framework import status
from rest_framework.test import APIClient, APIRequestFactory, APITestCase
from rest_framework.throttling import AnonRateThrottle

from config.testing import PASSWORD, make_user


class RefreshTokenRotationTests(APITestCase):
    """Q5: كل تجديد يُبطل الـ refresh القديم، وتسجيل الخروج يُبطل الحالي."""

    def setUp(self):
        make_user("patient", "patient")
        self.client = APIClient()
        response = self.client.post(
            "/api/auth/login/", {"username": "patient", "password": PASSWORD}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.refresh = response.data["refresh"]

    def refresh_with(self, token):
        return self.client.post("/api/auth/refresh/", {"refresh": token}, format="json")

    def test_refresh_rotates_and_old_token_is_rejected(self):
        first = self.refresh_with(self.refresh)
        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertIn("refresh", first.data)
        self.assertNotEqual(first.data["refresh"], self.refresh)

        reused = self.refresh_with(self.refresh)
        self.assertEqual(reused.status_code, status.HTTP_401_UNAUTHORIZED)

        self.assertEqual(self.refresh_with(first.data["refresh"]).status_code, status.HTTP_200_OK)

    def test_logout_blacklists_refresh_token(self):
        response = self.client.post("/api/auth/logout/", {"refresh": self.refresh}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.refresh_with(self.refresh).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_ignores_expired_access_token_header(self):
        # التطبيق قد يرسل access منتهياً — تسجيل الخروج لا يعتمد عليه
        self.client.credentials(HTTP_AUTHORIZATION="Bearer not-a-valid-token")
        response = self.client.post("/api/auth/logout/", {"refresh": self.refresh}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ClientIpTests(APITestCase):
    """H10: الـ throttling يعتمد على IP العميل الذي يضعه nginx في X-Forwarded-For."""

    @override_settings(REST_FRAMEWORK={"NUM_PROXIES": 1})
    def test_throttle_uses_ip_from_nginx(self):
        # nginx (axon-proxy.conf) يضع IP العميل وحده بعد استعادته من CF-Connecting-IP
        request = APIRequestFactory().get("/", HTTP_X_FORWARDED_FOR="203.0.113.7", REMOTE_ADDR="")
        self.assertEqual(AnonRateThrottle().get_ident(request), "203.0.113.7")
