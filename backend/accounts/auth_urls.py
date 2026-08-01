"""Authentication endpoints, mounted at ``/api/v1/auth/``.

Separate from ``accounts.urls`` (``/api/v1/accounts/``) because these are about
holding a credential rather than about the user resource, and because the
session cookie's path is the whole ``/api/v1/`` prefix either way.
"""

from django.urls import path
from django.urls.resolvers import URLPattern, URLResolver
from rest_framework.routers import DefaultRouter

from accounts.views import DeviceSessionViewSet, LoginView, LogoutView

router = DefaultRouter()
router.register(r"sessions", DeviceSessionViewSet, basename="device-sessions")

urlpatterns: list[URLPattern | URLResolver] = [
	path("login/", LoginView.as_view(), name="auth-login"),
	path("logout/", LogoutView.as_view(), name="auth-logout"),
]
urlpatterns += router.urls
