"""nginx يقدّم نسخة الويب (PWA) من /app/ و /firebase-messaging-sw.js
(deploy/nginx-axon-web.conf) قبل أن يصل الطلب إلى Django. أي مسار Django
جديد يبدأ بهما سيُحجب بصمت في الإنتاج، فيفشل هذا الاختبار بدل ذلك."""

from django.conf import settings
from django.test import SimpleTestCase
from django.urls import Resolver404, resolve

WEB_PATHS = ["/app", "/app/", "/app/index.html", "/app/x/y", "/firebase-messaging-sw.js"]


class WebPathsDoNotClashTests(SimpleTestCase):
    def test_django_has_no_url_under_the_web_app_paths(self):
        for path in WEB_PATHS:
            with self.subTest(path=path), self.assertRaises(Resolver404):
                resolve(path)

    def test_static_and_media_prefixes_are_elsewhere(self):
        for prefix in (settings.STATIC_URL, settings.MEDIA_URL):
            self.assertFalse(prefix.startswith("/app"), prefix)


class ApiNoStoreTests(SimpleTestCase):
    def test_api_responses_are_not_cacheable(self):
        response = self.client.post("/api/auth/login/", {}, content_type="application/json")
        self.assertEqual(response["Cache-Control"], "no-store")

    def test_non_api_pages_keep_their_own_caching(self):
        response = self.client.get("/privacy/")
        self.assertNotEqual(response.get("Cache-Control"), "no-store")
