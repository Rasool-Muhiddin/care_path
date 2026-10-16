from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle, UserRateThrottle
from rest_framework.views import APIView

from .deletion import DeletionBlocked, delete_account, deletion_block

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
        return Response(status=status.HTTP_204_NO_CONTENT)


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
