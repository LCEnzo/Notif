from __future__ import annotations

import json
import sqlite3
from collections import deque
from pathlib import Path
from typing import Any

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

_CADDY_LOG_MAX_LINES = 200
_CADDY_LOG_DEFAULT_LINES = 50
_CADDY_LOG_MAX_BYTES = 2_000_000


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
@permission_classes([IsAdminUser])
def caddy_access_logs(request: Request) -> Response:
	try:
		limit = int(request.query_params.get("limit", _CADDY_LOG_DEFAULT_LINES))
	except ValueError:
		return Response({"detail": "limit must be an integer."}, status=400)
	if limit < 1 or limit > _CADDY_LOG_MAX_LINES:
		return Response({"detail": f"limit must be between 1 and {_CADDY_LOG_MAX_LINES}."}, status=400)

	log_path = Path(settings.CADDY_ACCESS_LOG_PATH)
	if not log_path.exists():
		return Response({"configured_path": str(log_path), "results": []})
	if not log_path.is_file():
		return Response({"detail": "Configured Caddy access log path is not a file."}, status=400)

	entries = _read_caddy_log_tail(log_path, limit)
	return Response({"configured_path": str(log_path), "results": entries})


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


def _read_caddy_log_tail(log_path: Path, limit: int) -> list[dict[str, Any]]:
	file_size = log_path.stat().st_size
	start = max(0, file_size - _CADDY_LOG_MAX_BYTES)
	lines: deque[str] = deque(maxlen=limit)

	with log_path.open("rb") as log_file:
		log_file.seek(start)
		if start > 0:
			log_file.readline()
		for raw_line in log_file:
			line = raw_line.decode("utf-8", errors="replace").strip()
			if line:
				lines.append(line)

	entries: list[dict[str, Any]] = []
	for line in reversed(lines):
		try:
			data = json.loads(line)
		except json.JSONDecodeError:
			data = {"raw": line}
		if isinstance(data, dict):
			entries.append(data)
		else:
			entries.append({"raw": data})
	return entries
