from rest_framework.routers import DefaultRouter

from .views import CaseProgressNoteViewSet, CaseViewSet, WeeklyEpisodeLogViewSet

router = DefaultRouter()
router.register("cases", CaseViewSet, basename="case")
router.register(
    "case-progress-notes", CaseProgressNoteViewSet, basename="case-progress-note"
)
router.register(
    "weekly-episode-logs", WeeklyEpisodeLogViewSet, basename="weekly-episode-log"
)

urlpatterns = router.urls