from rest_framework.routers import DefaultRouter

from .views import (
    AttackEventViewSet,
    AttackLogConfirmationViewSet,
    CaseProgressNoteViewSet,
    CaseViewSet,
    WeeklyEpisodeLogViewSet,
)

router = DefaultRouter()
router.register("cases", CaseViewSet, basename="case")
router.register(
    "case-progress-notes", CaseProgressNoteViewSet, basename="case-progress-note"
)
router.register(
    "weekly-episode-logs", WeeklyEpisodeLogViewSet, basename="weekly-episode-log"
)
router.register("attack-events", AttackEventViewSet, basename="attack-event")
router.register(
    "attack-log-confirmations",
    AttackLogConfirmationViewSet,
    basename="attack-log-confirmation",
)

urlpatterns = router.urls
