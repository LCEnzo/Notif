"""notif URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
	https://docs.djangoproject.com/en/4.0/topics/http/urls/
Examples:
Function views
	1. Add an import:  from my_app import views
	2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
	1. Add an import:  from other_app.views import Home
	2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
	1. Import the include() function: from django.urls import include, path
	2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""

from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView
from rest_framework.permissions import AllowAny

from accounts.views import (
	DevBootstrapTokenObtainPairView,
	ThrottledTokenRefreshView,
	ThrottledTokenVerifyView,
)

urlpatterns = [
	path("admin/", admin.site.urls),
	path("api/v1/accounts/", include("accounts.urls")),
	path("api/v1/monitoring/", include("monitoring.urls")),
	# JWT config
	path("api/v1/token/", DevBootstrapTokenObtainPairView.as_view(), name="token_obtain_pair"),  # type: ignore
	path("api/v1/token/refresh/", ThrottledTokenRefreshView.as_view(), name="token_refresh"),  # type: ignore
	path("api/v1/token/verify/", ThrottledTokenVerifyView.as_view(), name="token_verify"),  # type: ignore
	# OpenAPI schema & docs (public — no auth so agents can discover the API)
	path("api/v1/schema/", SpectacularAPIView.as_view(permission_classes=[AllowAny]), name="schema"),  # type: ignore[arg-type]
	path(
		"api/v1/docs/",
		SpectacularSwaggerView.as_view(permission_classes=[AllowAny], url_name="schema"),
		name="swagger-ui",
	),  # type: ignore[arg-type]
	path("api/v1/redoc/", SpectacularRedocView.as_view(permission_classes=[AllowAny], url_name="schema"), name="redoc"),  # type: ignore[arg-type]
]
