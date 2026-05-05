from django.urls import path
from django.urls.resolvers import URLPattern, URLResolver
from rest_framework.routers import DefaultRouter

from ops.views import SystemEventViewSet, download_sqlite_backup

router = DefaultRouter()
router.register(r"events", SystemEventViewSet, basename="ops-events")

urlpatterns: list[URLPattern | URLResolver] = [
	path("backup/sqlite/", download_sqlite_backup, name="download-sqlite-backup"),
]
urlpatterns += router.urls
