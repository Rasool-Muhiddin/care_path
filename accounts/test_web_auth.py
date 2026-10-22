from django.conf import settings
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APIClient, APITestCase

from config.testing import PASSWORD, make_user

WEB = {"HTTP_X_AXON_CLIENT": "web"}
COOKIE = settings.AUTH_REFRESH_COOKIE_NAME


@override_settings(DEBUG=False, ALLOWED_HOSTS=["testserver"])
class WebRefreshCookieTests(APITestCase):
    """نسخة الويب: refresh في كوكي HttpOnly، و access في الجسم فقط."""

    def setUp(self):
        make_user("patient", "patient")
        self.client = APIClient()

    def login(self, **extra):
        return self.client.post(
            "/api/auth/login/", {"username": "patient", "password": PASSWORD}, format="json", **WEB, **extra
        )

    @override_settings(AUTH_REFRESH_COOKIE_SECURE=True)
    def test_login_puts_refresh_in_httponly_cookie_not_body(self):
        response = self.login()
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)
        self.assertNotIn("refresh", response.data)
        cookie = response.cookies[COOKIE]
        self.assertTrue(cookie["httponly"])
        self.assertEqual(cookie["samesite"], "Strict")
        self.assertEqual(cookie["path"], "/api/auth/")
        self.assertTrue(cookie["secure"])

    def test_refresh_from_cookie_rotates_cookie(self):
        old = self.login().cookies[COOKIE].value
        response = self.client.post("/api/auth/refresh/", **WEB)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)
        self.assertNotIn("refresh", response.data)
        new = response.cookies[COOKIE].value
        self.assertNotEqual(new, old)

        # الـ refresh القديم مُبطل بعد التدوير
        self.client.cookies[COOKIE] = old
        reused = self.client.post("/api/auth/refresh/", **WEB)
        self.assertEqual(reused.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reused.cookies[COOKIE].value, "")

    def test_refresh_without_cookie_is_401(self):
        response = self.client.post("/api/auth/refresh/", **WEB)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_blacklists_cookie_and_clears_it(self):
        token = self.login().cookies[COOKIE].value
        response = self.client.post("/api/auth/logout/", **WEB)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.cookies[COOKIE].value, "")
        self.client.cookies[COOKIE] = token
        self.assertEqual(
            self.client.post("/api/auth/refresh/", **WEB).status_code, status.HTTP_401_UNAUTHORIZED
        )

    def test_foreign_origin_is_rejected(self):
        self.login()
        evil = {"HTTP_ORIGIN": "https://evil.example"}
        self.assertEqual(self.client.post("/api/auth/refresh/", **WEB, **evil).status_code, 403)
        self.assertEqual(self.client.post("/api/auth/logout/", **WEB, **evil).status_code, 403)
        self.assertEqual(self.login(**evil).status_code, 403)

    def test_same_origin_is_accepted(self):
        self.login()
        same = {"HTTP_ORIGIN": "http://testserver"}
        self.assertEqual(self.client.post("/api/auth/refresh/", **WEB, **same).status_code, 200)

    def test_cookie_alone_without_web_header_is_not_used(self):
        # بلا الـ header يبقى المسار القديم: الكوكي لا يكفي (حماية CSRF)
        self.login()
        response = self.client.post("/api/auth/refresh/")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_delete_account_clears_cookie(self):
        access = self.login().data["access"]
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        response = self.client.post("/api/auth/delete-account/", {"password": PASSWORD}, format="json", **WEB)
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(response.cookies[COOKIE].value, "")


class NativeFlowUnchangedTests(APITestCase):
    """التطبيقات (بلا X-Axon-Client): refresh في الجسم ولا كوكي."""

    def test_login_and_refresh_use_body(self):
        make_user("patient", "patient")
        response = self.client.post(
            "/api/auth/login/", {"username": "patient", "password": PASSWORD}, format="json"
        )
        self.assertIn("refresh", response.data)
        self.assertNotIn(COOKIE, response.cookies)
        refreshed = self.client.post("/api/auth/refresh/", {"refresh": response.data["refresh"]}, format="json")
        self.assertEqual(refreshed.status_code, status.HTTP_200_OK)
        self.assertIn("refresh", refreshed.data)
        self.assertNotIn(COOKIE, refreshed.cookies)
