from django.contrib.auth import get_user_model
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import UserRole
from .permissions import IsDoctorOrEngineer, IsEngineer
from .serializers import (
    DoctorListSerializer,
    EngineerListSerializer,
    PatientListSerializer,
    RegisterSerializer,
    UserSerializer,
)

User = get_user_model()


class RegisterView(generics.CreateAPIView):
    """POST /api/auth/register/  -- تسجيل مريض أو طبيب جديد (وليس مهندس)."""

    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]


class MeView(APIView):
    """
    GET /api/auth/me/
    يُستدعى من تطبيق Flutter مباشرة بعد تسجيل الدخول لمعرفة دور المستخدم
    (role) وتوجيهه للواجهة الصحيحة عبر الراوتر.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)


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
        return User.objects.filter(role=UserRole.PATIENT).order_by("first_name", "last_name")


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
        return User.objects.filter(role=UserRole.ENGINEER).order_by("first_name", "last_name")


class DoctorListView(generics.ListAPIView):
    """قائمة الأطباء الكاملة للمهندس، بما في ذلك الطبيب بلا حالات بعد."""

    serializer_class = DoctorListSerializer
    permission_classes = [permissions.IsAuthenticated, IsEngineer]

    def get_queryset(self):
        return User.objects.filter(role=UserRole.DOCTOR).order_by("first_name", "last_name")
