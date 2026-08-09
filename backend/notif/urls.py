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

from django.conf import settings
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView
from rest_framework.permissions import AllowAny

from notif.config import settings as app_settings
from ops.views import ClientEventView

_admin_url = app_settings.DJANGO_ADMIN_URL.lstrip("/")
if not _admin_url.endswith("/"):
	_admin_url += "/"

urlpatterns = [
	path(_admin_url, admin.site.urls),
	path("api/v1/auth/", include("accounts.auth_urls")),
	path("api/v1/accounts/", include("accounts.urls")),
	path("api/v1/monitoring/", include("monitoring.urls")),
	path("api/v1/ops/", include("ops.urls")),
	path("api/v1/client-events/", ClientEventView.as_view(), name="client-events"),
	# OpenAPI schema & docs (public — no auth so agents can discover the API)
	path("api/v1/schema/", SpectacularAPIView.as_view(permission_classes=[AllowAny]), name="schema"),
	path(
		"api/v1/docs/",
		SpectacularSwaggerView.as_view(permission_classes=[AllowAny], url_name="schema"),
		name="swagger-ui",
	),
	path("api/v1/redoc/", SpectacularRedocView.as_view(permission_classes=[AllowAny], url_name="schema"), name="redoc"),
]

if settings.DEBUG:
	urlpatterns += [
		path("silk/", include("silk.urls", namespace="silk")),
	]
