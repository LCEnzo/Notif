from __future__ import annotations

import sqlite3

from django.conf import settings
from django.db import connection
from django.http import HttpResponse
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.filters import OrderingFilter
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import IsAdminUser
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.viewsets import ReadOnlyModelViewSet

from ops.models import SystemEvent
from ops.serializers import SystemEventSerializer


class IsSuperUser(IsAdminUser):
	def has_permission(self, request: Request, view) -> bool:
		return bool(request.user and request.user.is_authenticated and request.user.is_superuser)


class SystemEventPagination(PageNumberPagination):
	page_size = 50
	page_size_query_param = "page_size"
	max_page_size = 200


class SystemEventViewSet(ReadOnlyModelViewSet):
	permission_classes = [IsAdminUser]
	serializer_class = SystemEventSerializer
	pagination_class = SystemEventPagination
	filter_backends = [OrderingFilter]
	ordering_fields = ["created_at", "id", "level", "source", "kind"]
	ordering = ["-created_at", "-id"]

	def get_queryset(self):
		queryset = SystemEvent.objects.all()

		level = self.request.query_params.get("level")
		if level:
			queryset = queryset.filter(level=level)

		source = self.request.query_params.get("source")
		if source:
			queryset = queryset.filter(source=source)

		kind = self.request.query_params.get("kind")
		if kind:
			queryset = queryset.filter(kind=kind)

		return queryset


@api_view(["GET"])
@permission_classes([IsSuperUser])
def download_sqlite_backup(request: Request) -> HttpResponse | Response:
	db_config = settings.DATABASES["default"]
	if db_config["ENGINE"] != "django.db.backends.sqlite3":
		return Response({"detail": "SQLite backup is only available for sqlite3 databases."}, status=400)

	connection.ensure_connection()
	source = connection.connection
	if not isinstance(source, sqlite3.Connection):
		return Response({"detail": "Active database connection is not sqlite3."}, status=400)
	data = source.serialize()

	timestamp = timezone.now().strftime("%Y%m%d-%H%M%S")
	response = HttpResponse(data, content_type="application/vnd.sqlite3")
	response["Content-Disposition"] = f'attachment; filename="notif-db-{timestamp}.sqlite3"'
	response["Cache-Control"] = "no-store"
	return response
