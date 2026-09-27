from django.urls import path

from .views import DeviceTokenView

urlpatterns = [
    path("fcm-token/", DeviceTokenView.as_view(), name="fcm-token"),
]
