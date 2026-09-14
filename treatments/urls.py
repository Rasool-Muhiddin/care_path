from rest_framework.routers import DefaultRouter

from .views import TreatmentSessionViewSet

router = DefaultRouter()
router.register("sessions", TreatmentSessionViewSet, basename="session")

urlpatterns = router.urls