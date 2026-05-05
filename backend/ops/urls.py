from django.urls import path
from django.urls.resolvers import URLPattern, URLResolver
from rest_framework.routers import DefaultRouter

from ops.views import SystemEventViewSet, caddy_access_logs, download_sqlite_backup

router = DefaultRouter()
router.register(r"events", SystemEventViewSet, basename="ops-events")

urlpatterns: list[URLPattern | URLResolver] = [
	path("backup/sqlite/", download_sqlite_backup, name="download-sqlite-backup"),
	path("logs/caddy/", caddy_access_logs, name="caddy-access-logs"),
]
urlpatterns += router.urls
