from rest_framework.routers import DefaultRouter

from .views import ClinicViewSet, DeviceTypeViewSet, DeviceViewSet

router = DefaultRouter()
router.register("clinics", ClinicViewSet, basename="clinic")
router.register("device-types", DeviceTypeViewSet, basename="device-type")
router.register("devices", DeviceViewSet, basename="device")

urlpatterns = router.urls