from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import DeviceToken
from .serializers import DeviceTokenSerializer


class DeviceTokenView(APIView):
    """
    POST /api/fcm-token/  {token, platform}
        يسجّل/يحدّث توكن FCM لهذا الجهاز ويربطه بالمستخدم الحالي. إن كان
        التوكن مسجّلاً سابقاً لمستخدم آخر (تسجيل خروج ثم دخول بحساب مختلف
        على نفس الجهاز) يُعاد ربطه بالمستخدم الحالي تلقائياً.

    DELETE /api/fcm-token/  {token}
        يُستدعى عند تسجيل الخروج — يحذف التوكن حتى لا يستمر الجهاز
        بتلقي إشعارات تخص حساباً لم يعد مسجَّلاً دخوله عليه.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        DeviceToken.objects.update_or_create(
            token=serializer.validated_data["token"],
            defaults={
                "user": request.user,
                "platform": serializer.validated_data["platform"],
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        token = request.data.get("token")
        if token:
            DeviceToken.objects.filter(token=token, user=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
