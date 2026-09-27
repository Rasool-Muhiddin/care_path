from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("accounts.urls")),
    path("api/", include("devices.urls")),
    path("api/", include("cases.urls")),
    path("api/", include("treatments.urls")),
    path("api/", include("feedback.urls")),
    path("api/", include("app_updates.urls")),
    path("api/", include("notifications.urls")),
    path('api/chat/', include('chat.urls')),
]

# تقديم ملفات media (مثل APK) مباشرة أثناء التطوير فقط؛ في الإنتاج يجب
# تقديمها عبر nginx/الخادم مباشرة وليس عبر Django.
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

# نقاط النهاية النهائية بعد هذا الربط (أمثلة):
#   POST /api/auth/register/
#   POST /api/auth/login/
#   GET  /api/auth/me/
#   GET  /api/clinics/            (مهندس فقط)
#   GET  /api/devices/
#   GET  /api/cases/
#   GET  /api/sessions/
#   GET  /api/feedback/