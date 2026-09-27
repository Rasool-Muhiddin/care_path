from rest_framework import permissions
from rest_framework.exceptions import NotFound
from rest_framework.generics import RetrieveAPIView

from .models import AppVersion, Platform
from .serializers import AppVersionSerializer


class LatestAppVersionView(RetrieveAPIView):
    """
    GET /api/app-version/latest/?platform=android

    متاح بدون تسجيل دخول (AllowAny) لأن فحص التحديث يجب أن يعمل من
    شاشة البداية قبل أي تسجيل دخول. يرجع آخر نسخة منشورة (أعلى
    version_code) لهذه المنصة، أو 404 إن لم تُنشر أي نسخة بعد —
    والتطبيق يتعامل مع الـ 404 على أنه "لا يوجد تحديث".
    """

    serializer_class = AppVersionSerializer
    permission_classes = [permissions.AllowAny]

    def get_object(self) -> AppVersion:
        platform = self.request.query_params.get("platform", Platform.ANDROID)
        version = (
            AppVersion.objects.filter(platform=platform, is_published=True)
            .order_by("-version_code")
            .first()
        )
        if version is None:
            raise NotFound("لا توجد نسخة منشورة بعد")
        return version
