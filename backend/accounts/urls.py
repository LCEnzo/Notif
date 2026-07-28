from django.urls import path
from rest_framework.routers import DefaultRouter

from accounts.views import (
	PasswordResetConfirmView,
	PasswordResetRequestView,
	RefreshSessionViewSet,
	UserViewSet,
)

router = DefaultRouter()
router.register(r"users", UserViewSet, basename="users")
router.register(r"sessions", RefreshSessionViewSet, basename="refresh-sessions")

urlpatterns = router.urls
urlpatterns += [
	path(
		"password/reset/",
		PasswordResetRequestView.as_view(),
		name="password-reset",
	),
	path(
		"password/reset/confirm/",
		PasswordResetConfirmView.as_view(),
		name="password-reset-confirm",
	),
]
