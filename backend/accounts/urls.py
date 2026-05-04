from django.urls import path
from rest_framework.routers import DefaultRouter

from accounts.views import (
	PasswordResetConfirmView,
	PasswordResetRequestView,
	UserViewSet,
)

router = DefaultRouter()
router.register(r"users", UserViewSet, basename="users")

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
