"""
مصادقة نسخة الويب (PWA): الـ refresh token في كوكي HttpOnly بدل جسم الرد.

تطبيقات أندرويد/iOS لا ترسل الـ header أدناه، فتبقى على المسار القديم
(refresh في الجسم) بلا أي تغيير. نسخة الويب ترسل `X-Axon-Client: web`
مع كل طلب، فيصبح:

- login/   : access في الجسم، و refresh في الكوكي فقط (لا يراه JavaScript).
- refresh/ : الـ refresh يُقرأ من الكوكي، والجديد (ROTATE) يُكتب فيه.
- logout/  : يُبطل refresh الكوكي (blacklist) ويمسح الكوكي.
- delete-account/ : يمسح الكوكي بعد نجاح الحذف.

الحماية من CSRF للمسارات التي تعتمد على الكوكي (ثلاث طبقات):
1. SameSite=Strict: المتصفح لا يرسل الكوكي مع أي طلب من موقع آخر.
2. header مخصّص إلزامي: موقع آخر لا يستطيع إضافته بلا preflight من CORS،
   والخادم لا يسمح بأصول أخرى في الإنتاج.
3. فحص Origin: إن أرسله المتصفح يجب أن يطابق أصل الخادم نفسه.
"""

from django.conf import settings

WEB_CLIENT_HEADER = "HTTP_X_AXON_CLIENT"
WEB_CLIENT_VALUE = "web"


def is_web_client(request) -> bool:
    return request.META.get(WEB_CLIENT_HEADER) == WEB_CLIENT_VALUE


def is_trusted_origin(request) -> bool:
    """Origin غائب (بعض الطلبات من نفس الأصل) = مقبول؛ وإلا يجب أن يكون أصل
    الخادم نفسه أو أصلاً مُدرجاً صراحةً. في التطوير (DEBUG) يُقبل أي أصل
    لأن flutter run -d chrome يعمل على منفذ مختلف."""
    origin = request.META.get("HTTP_ORIGIN")
    if origin is None:
        return True
    if settings.DEBUG:
        return True
    allowed = {
        f"{request.scheme}://{request.get_host()}",
        *settings.CSRF_TRUSTED_ORIGINS,
        *settings.CORS_ALLOWED_ORIGINS,
    }
    return origin in allowed


def set_refresh_cookie(response, token: str) -> None:
    response.set_cookie(
        settings.AUTH_REFRESH_COOKIE_NAME,
        token,
        max_age=int(settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"].total_seconds()),
        path=settings.AUTH_REFRESH_COOKIE_PATH,
        secure=settings.AUTH_REFRESH_COOKIE_SECURE,
        httponly=True,
        samesite=settings.AUTH_REFRESH_COOKIE_SAMESITE,
    )


def clear_refresh_cookie(response) -> None:
    response.delete_cookie(
        settings.AUTH_REFRESH_COOKIE_NAME,
        path=settings.AUTH_REFRESH_COOKIE_PATH,
        samesite=settings.AUTH_REFRESH_COOKIE_SAMESITE,
    )


def move_refresh_to_cookie(response) -> None:
    """رد login/refresh ناجح: الـ refresh يخرج من الجسم إلى الكوكي."""
    token = response.data.pop("refresh", None)
    if token:
        set_refresh_cookie(response, token)


def refresh_from_cookie(request):
    return request.COOKIES.get(settings.AUTH_REFRESH_COOKIE_NAME)
