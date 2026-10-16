from django.urls import path
from rest_framework_simplejwt.views import TokenBlacklistView, TokenObtainPairView, TokenRefreshView

from .views import (
    DeleteAccountView,
    DoctorListView,
    EngineerListView,
    MeView,
    PatientListView,
    RegisterView,
)

urlpatterns = [
    path("auth/register/", RegisterView.as_view(), name="register"),
    path("auth/login/", TokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    # يُبطل الـ refresh token عند تسجيل الخروج: body {"refresh": "..."}
    path("auth/logout/", TokenBlacklistView.as_view(), name="token_blacklist"),
    path("auth/me/", MeView.as_view(), name="me"),
    path("auth/delete-account/", DeleteAccountView.as_view(), name="delete_account"),
    path("patients/", PatientListView.as_view(), name="patient_list"),
    path("doctors/", DoctorListView.as_view(), name="doctor_list"),
    path("engineers/", EngineerListView.as_view(), name="engineer_list"),
]
