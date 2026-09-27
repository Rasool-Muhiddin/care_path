from django.urls import path

from .views import LatestAppVersionView

urlpatterns = [
    path("app-version/latest/", LatestAppVersionView.as_view(), name="app-version-latest"),
]
