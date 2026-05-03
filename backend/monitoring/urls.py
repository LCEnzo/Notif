from django.urls import include, path  # noqa: F401
from rest_framework.routers import DefaultRouter

from monitoring.views import (
	LinkViewSet,
	NotificationViewSet,
	StrategyViewSet,
	get_strat_choices,
	health_check,
	status_check,
	trigger_scrape,
)

router = DefaultRouter()
router.register(r"links", LinkViewSet, basename="links")
router.register(r"strategies", StrategyViewSet, basename="strategies")
router.register(r"notifications", NotificationViewSet, basename="notifications")

urlpatterns = router.urls

urlpatterns += [
	path("strat-choices", get_strat_choices, name="get-strat-choices"),
	path("trigger-scrape/", trigger_scrape, name="trigger-scrape"),
	path("health/", health_check, name="health-check"),
	path("status/", status_check, name="status-check"),
]
