from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, status
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle, UserRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.views import TokenBlacklistView, TokenObtainPairView, TokenRefreshView

from .deletion import DeletionBlocked, delete_account, deletion_block
from .web_auth import (
    clear_refresh_cookie,
    is_trusted_origin,
    is_web_client,
    move_refresh_to_cookie,
    refresh_from_cookie,
)

from .models import UserRole
from .permissions import IsDoctorOrEngineer, IsDoctorOrEngineerManager, IsEngineer
from .serializers import (
    DoctorListSerializer,
    EngineerListSerializer,
    PatientListSerializer,
    RegisterSerializer,
    DeleteAccountSerializer,
    UserSerializer,
)

User = get_user_model()


class RegisterView(generics.CreateAPIView):
    """
    POST /api/auth/register/
    إنشاء حساب مريض/طبيب. مقيَّد بمن سجّل دخوله كطبيب أو مدير المهندسين —
    لا يوجد تسجيل عام بدون مصادقة، حتى لا يستطيع أي شخص إنشاء حساب طبيب
    والوصول لبيانات المرضى. القيود حسب دور المنشئ داخل RegisterSerializer.
    """

    serializer_class = RegisterSerializer
    permission_classes = [permissions.IsAuthenticated, IsDoctorOrEngineerManager]


def _web_origin_rejected():
    return Response({"detail": "Origin غير مسموح."}, status=status.HTTP_403_FORBIDDEN)


def _invalid_refresh_cookie(detail):
    response = Response(
        {"detail": detail, "code": "token_not_valid"}, status=status.HTTP_401_UNAUTHORIZED
    )
    clear_refresh_cookie(response)
    return response


class LoginView(TokenObtainPairView):
    """POST /api/auth/login/ — كما هو للتطبيقات؛ للويب الـ refresh في كوكي (web_auth)."""

    def post(self, request, *args, **kwargs):
        web = is_web_client(request)
        if web and not is_trusted_origin(request):
            return _web_origin_rejected()
        response = super().post(request, *args, **kwargs)
        if web and response.status_code == status.HTTP_200_OK:
            move_refresh_to_cookie(response)
        return response


class RefreshView(TokenRefreshView):
    """POST /api/auth/refresh/ — التطبيقات: {"refresh"} في الجسم. الويب: من الكوكي."""

    def post(self, request, *args, **kwargs):
        if not is_web_client(request):
            return super().post(request, *args, **kwargs)
        if not is_trusted_origin(request):
            return _web_origin_rejected()
        token = refresh_from_cookie(request)
        if not token:
            # لا جلسة على هذا المتصفح (أول فتح، أو بعد الخروج)
            return _invalid_refresh_cookie("لا توجد جلسة.")
        serializer = self.get_serializer(data={"refresh": token})
        try:
            serializer.is_valid(raise_exception=True)
        except (TokenError, AuthenticationFailed) as e:
            return _invalid_refresh_cookie(str(e.args[0]) if e.args else "Token is invalid")
        response = Response(serializer.validated_data, status=status.HTTP_200_OK)
        move_refresh_to_cookie(response)
        return response


class LogoutView(TokenBlacklistView):
    """POST /api/auth/logout/ — يُبطل الـ refresh (الجسم للتطبيقات، الكوكي للويب)."""

    def post(self, request, *args, **kwargs):
        if not is_web_client(request):
            return super().post(request, *args, **kwargs)
        if not is_trusted_origin(request):
            return _web_origin_rejected()
        token = refresh_from_cookie(request)
        if token:
            serializer = self.get_serializer(data={"refresh": token})
            try:
                serializer.is_valid(raise_exception=True)
            except TokenError:
                pass  # منتهٍ أو مُبطل أصلاً — الخروج يكتمل على أي حال
        response = Response({}, status=status.HTTP_200_OK)
        clear_refresh_cookie(response)
        return response


class MeView(APIView):
    """
    GET /api/auth/me/
    يُستدعى من تطبيق Flutter مباشرة بعد تسجيل الدخول لمعرفة دور المستخدم
    (role) وتوجيهه للواجهة الصحيحة عبر الراوتر.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)


class DeleteAccountView(APIView):
    """
    GET  /api/auth/delete-account/  → {"can_delete": bool, "code", "detail"}
         يعرض التطبيق سبب المنع (إن وُجد) قبل طلب كلمة المرور.
    POST /api/auth/delete-account/  {"password": "..."} → 204
         يحذف الحساب نهائياً حسب قواعد accounts/deletion.py، ويُبطل كل
         refresh tokens ويحذف توكنات الإشعارات. 403 مع code إن كان ممنوعاً،
         و400 إن كانت كلمة المرور خاطئة.
    """

    permission_classes = [permissions.IsAuthenticated]
    # حد إضافي على محاولات كلمة المرور (توكن مسروق لا يكفي لتخمينها)
    throttle_classes = [UserRateThrottle, ScopedRateThrottle]
    throttle_scope = "delete_account"

    def get(self, request):
        blocked = deletion_block(request.user)
        if blocked:
            return Response({"can_delete": False, "code": blocked.code, "detail": blocked.message})
        return Response({"can_delete": True, "code": None, "detail": None})

    def post(self, request):
        serializer = DeleteAccountSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        try:
            delete_account(request.user)
        except DeletionBlocked as blocked:
            return Response({"code": blocked.code, "detail": blocked.message}, status=status.HTTP_403_FORBIDDEN)
        response = Response(status=status.HTTP_204_NO_CONTENT)
        if is_web_client(request):
            clear_refresh_cookie(response)
        return response


class PatientListView(generics.ListAPIView):
    """
    GET /api/patients/
    قائمة بكل المرضى المسجلين بالنظام — يستخدمها الطبيب/المهندس عند
    إنشاء حالة (Case) جديدة لاختيار المريض المعني. محمية بحيث لا يصل
    إليها المريض نفسه (لا داعي أن يرى المريض قائمة بكل المرضى الآخرين).
    """

    serializer_class = PatientListSerializer
    permission_classes = [permissions.IsAuthenticated, IsDoctorOrEngineer]

    def get_queryset(self):
        return User.objects.filter(role=UserRole.PATIENT).order_by("first_name", "last_name", "id")


class EngineerListView(generics.ListAPIView):
    """
    GET /api/engineers/
    قائمة بمهندسي الفريق — تُستخدم لاختيار "المهندس المسؤول" عند إنشاء
    عيادة جديدة. محمية بحيث لا يصل إليها إلا المهندسون أنفسهم (لا داعي
    للطبيب أو المريض رؤية قائمة الفريق الداخلي).
    """

    serializer_class = EngineerListSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]

    def get_queryset(self):
        return User.objects.filter(role=UserRole.ENGINEER).order_by("first_name", "last_name", "id")


class DoctorListView(generics.ListAPIView):
    """قائمة الأطباء الكاملة للمهندس، بما في ذلك الطبيب بلا حالات بعد."""

    serializer_class = DoctorListSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]

    def get_queryset(self):
        return User.objects.filter(role=UserRole.DOCTOR).order_by("first_name", "last_name", "id")
