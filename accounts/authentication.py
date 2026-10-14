from datetime import timedelta

from django.utils import timezone
from rest_framework_simplejwt.authentication import JWTAuthentication

from .models import User

# لا نكتب على قاعدة البيانات مع كل طلب — يكفي تحديث واحد بالساعة
LAST_SEEN_RESOLUTION = timedelta(hours=1)


class TrackingJWTAuthentication(JWTAuthentication):
    """
    JWTAuthentication + تحديث User.last_seen_at عند أي طلب مصادَق (أي
    استخدام فعلي للتطبيق، بما فيه النسخ القديمة). يعتمد عليه تذكير
    تسجيل النوبات لمعرفة المريض الذي لم يفتح التطبيق منذ أيام.
    """

    def authenticate(self, request):
        result = super().authenticate(request)
        if result is not None:
            mark_seen(result[0])
        return result


def mark_seen(user):
    now = timezone.now()
    if user.last_seen_at is None or now - user.last_seen_at >= LAST_SEEN_RESOLUTION:
        User.objects.filter(pk=user.pk).update(last_seen_at=now)
        user.last_seen_at = now
