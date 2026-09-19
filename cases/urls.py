from rest_framework.routers import DefaultRouter

from .views import CaseProgressNoteViewSet, CaseViewSet

router = DefaultRouter()
router.register("cases", CaseViewSet, basename="case")
router.register(
    "case-progress-notes", CaseProgressNoteViewSet, basename="case-progress-note"
)

urlpatterns = router.urls