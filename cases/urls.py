from rest_framework.routers import DefaultRouter

from .views import (
    AttackEventViewSet,
    AttackLogConfirmationViewSet,
    CaseProgressNoteViewSet,
    CaseViewSet,
)

router = DefaultRouter()
router.register("cases", CaseViewSet, basename="case")
router.register(
    "case-progress-notes", CaseProgressNoteViewSet, basename="case-progress-note"
)
router.register("attack-events", AttackEventViewSet, basename="attack-event")
router.register(
    "attack-log-confirmations",
    AttackLogConfirmationViewSet,
    basename="attack-log-confirmation",
)

urlpatterns = router.urls
