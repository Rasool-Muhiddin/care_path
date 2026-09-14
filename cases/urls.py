from rest_framework.routers import DefaultRouter

from .views import CaseViewSet

router = DefaultRouter()
router.register("cases", CaseViewSet, basename="case")

urlpatterns = router.urls