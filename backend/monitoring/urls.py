from django.urls import include, path  # noqa: F401
from rest_framework.routers import DefaultRouter

from monitoring.views import (
	LinkViewSet,
	StrategyViewSet,
)

router = DefaultRouter()
router.register(r'links', LinkViewSet, basename="links")
router.register(r'strategies', StrategyViewSet, basename="strategies")

urlpatterns = router.urls

urlpatterns += [
	path("strat-choices", get_strat_choices, name='get-strat-choices'),
]
