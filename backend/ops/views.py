from __future__ import annotations

import contextlib
import json
import os
import re
import sqlite3
import tempfile
from collections import deque
from collections.abc import Iterator
from pathlib import Path
from typing import TYPE_CHECKING, Any

from django.conf import settings
from django.db import connection
from django.db.models.query import QuerySet
from django.http import HttpResponse, StreamingHttpResponse
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework.decorators import api_view, permission_classes
from rest_framework.filters import OrderingFilter
from rest_framework.pagination import PageNumberPagination
from rest_framework.parsers import JSONParser
from rest_framework.permissions import AllowAny, IsAdminUser
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework.viewsets import ReadOnlyModelViewSet

from commons.network import client_ip
from ops.models import SystemEvent
from ops.serializers import (
	CaddyAccessLogResponseSerializer,
	ClientEventAcceptedSerializer,
	ClientEventSerializer,
	SystemEventSerializer,
)

if TYPE_CHECKING:
	_SystemEventReadOnlyModelViewSet = ReadOnlyModelViewSet[SystemEvent]
else:
	_SystemEventReadOnlyModelViewSet = ReadOnlyModelViewSet

_CADDY_LOG_MAX_LINES = 200
_CADDY_LOG_DEFAULT_LINES = 50
# Caddy rolls the active access log at 10 MiB and keeps 5 generations. 32 MiB
# of tail scan covers the entire active file plus headroom under heavy traffic;
# memory stays bounded by the deque(maxlen=limit), not by this window.
_CADDY_LOG_MAX_BYTES = 32 * 1024 * 1024
_BACKUP_STREAM_CHUNK = 64 * 1024
_CLIENT_EVENT_SOURCE = "frontend"
# Hard ceiling on rows the anonymous client-event sink can keep. The per-IP
# throttle bounds the write *rate*, but rows were permanent, so 30/min/IP was
# still unbounded growth distributed across arbitrary IPs. At the cap the sink
# evicts its oldest rows (ring buffer) rather than rejecting: after an outage
# the newest reports are the ones that matter, and a flood then costs the
# attacker their own diagnostics, not ours - other sources' rows are untouched.
_CLIENT_EVENT_MAX_ROWS = 5000
_SECRET_PATTERNS = [
	re.compile(r"Bearer\s+[A-Za-z0-9._~+/=-]+", re.IGNORECASE),
	re.compile(r"(notif_refresh=)[^;\s]+", re.IGNORECASE),
	re.compile(r"([?&](?:access|refresh|token|password)=)[^&\s]+", re.IGNORECASE),
	re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"),
]


class IsSuperUser(IsAdminUser):
	def has_permission(self, request: Request, view: Any) -> bool:
		return bool(request.user and request.user.is_authenticated and request.user.is_superuser)


class SystemEventPagination(PageNumberPagination):
	page_size = 50
	page_size_query_param = "page_size"
	max_page_size = 200


class SystemEventViewSet(_SystemEventReadOnlyModelViewSet):
	permission_classes = [IsAdminUser]
	serializer_class = SystemEventSerializer
	pagination_class = SystemEventPagination
	filter_backends = [OrderingFilter]
	ordering_fields = ["created_at", "id", "level", "source", "kind"]
	ordering = ["-created_at", "-id"]

	def get_queryset(self) -> QuerySet[SystemEvent]:
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


class ClientEventView(APIView):
	permission_classes = [AllowAny]
	# JSON only, for the same reason the token views are JSON only: this endpoint
	# is anonymous and writes a persistent SystemEvent row per request. With the
	# default form parsers a cross-site page can POST here via a hidden form,
	# which is a CORS simple request and so never preflighted, and the per-IP
	# throttle is charged to whichever visitor's browser made the call - so the
	# writes distribute across arbitrary client IPs. A form cannot produce a
	# JSON content type, so refusing to parse anything else closes it.
	parser_classes = [JSONParser]
	throttle_classes = [ScopedRateThrottle]
	throttle_scope = "client_events"

	@extend_schema(
		request=ClientEventSerializer,
		responses={202: ClientEventAcceptedSerializer},
	)
	def post(self, request: Request) -> Response:
		serializer = ClientEventSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		event = serializer.validated_data
		category = str(event["category"])
		message = _scrub_client_text(str(event.get("message", "")), max_length=500)
		if not message:
			message = f"Frontend reported {category}."

		_evict_client_events_over_cap()
		SystemEvent.objects.create(
			level=SystemEvent.Level.WARNING,
			source=_CLIENT_EVENT_SOURCE,
			kind=f"client-{category}"[:80],
			message=message,
			details={
				"category": category,
				"route": _scrub_client_text(str(event.get("route", "")), max_length=200),
				"endpoint": _scrub_client_text(str(event.get("endpoint", "")), max_length=200),
				"request_id": _scrub_client_text(str(event.get("request_id", "")), max_length=120),
				"contract_path": _scrub_client_text(str(event.get("contract_path", "")), max_length=200),
				"expected": _scrub_client_text(str(event.get("expected", "")), max_length=500),
				"actual": _scrub_client_text(str(event.get("actual", "")), max_length=500),
				"app_version": _scrub_client_text(str(event.get("app_version", "")), max_length=60),
				"git_hash": _scrub_client_text(str(event.get("git_hash", "")), max_length=80),
				"browser": _scrub_client_text(str(event.get("browser", "")), max_length=200),
				"stack": _scrub_client_text(str(event.get("stack", "")), max_length=2000),
				"remote_ip": client_ip(request),
			},
		)
		return Response({"status": "accepted"}, status=202)


def _evict_client_events_over_cap() -> None:
	"""Delete the oldest frontend rows so one more insert stays within the cap.

	Two concurrent requests can both pass the count check and overshoot by a
	row; the next insert evicts back down, so the bound holds within the
	throttle's concurrency, not exactly. Overflow is tiny by construction
	(cap plus at most a few in-flight requests), so the id list stays bounded.
	"""
	frontend_events = SystemEvent.objects.filter(source=_CLIENT_EVENT_SOURCE)
	overflow = frontend_events.count() - _CLIENT_EVENT_MAX_ROWS + 1
	if overflow <= 0:
		return
	evict_ids = list(frontend_events.order_by("id").values_list("id", flat=True)[:overflow])
	SystemEvent.objects.filter(id__in=evict_ids).delete()


@extend_schema(responses={200: CaddyAccessLogResponseSerializer})
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


@extend_schema(responses={200: OpenApiResponse(response=OpenApiTypes.BINARY, description="SQLite backup file")})
@api_view(["GET"])
@permission_classes([IsSuperUser])
def download_sqlite_backup(request: Request) -> HttpResponse | Response | StreamingHttpResponse:
	db_config = settings.DATABASES["default"]
	if db_config["ENGINE"] != "django.db.backends.sqlite3":
		return Response({"detail": "SQLite backup is only available for sqlite3 databases."}, status=400)

	connection.ensure_connection()
	source = connection.connection
	if not isinstance(source, sqlite3.Connection):
		return Response({"detail": "Active database connection is not sqlite3."}, status=400)

	fd, tmp_path = tempfile.mkstemp(suffix=".sqlite3", prefix="notif-backup-")
	os.close(fd)
	try:
		_write_sqlite_backup(source, str(db_config["NAME"]), tmp_path)
		size_bytes = Path(tmp_path).stat().st_size
	except Exception:
		_unlink_quiet(tmp_path)
		raise

	user = request.user
	audit_context: dict[str, Any] = {
		"user_id": user.pk,
		"username": user.get_username(),
		"size_bytes": size_bytes,
		"remote_ip": client_ip(request),
	}
	SystemEvent.objects.create(
		level=SystemEvent.Level.INFO,
		source="ops.download_sqlite_backup",
		kind="audit-prepared",
		message=f"SQLite backup prepared for {user.get_username()} ({size_bytes} bytes).",
		details=audit_context,
	)

	timestamp = timezone.now().strftime("%Y%m%d-%H%M%S")
	response = StreamingHttpResponse(
		_stream_and_unlink(tmp_path, audit_context),
		content_type="application/vnd.sqlite3",
	)
	response["Content-Disposition"] = f'attachment; filename="notif-db-{timestamp}.sqlite3"'
	response["Content-Length"] = str(size_bytes)
	response["Cache-Control"] = "no-store"
	return response


def _write_sqlite_backup(source: sqlite3.Connection, db_name: str, tmp_path: str) -> None:
	"""Copy the active sqlite3 database into ``tmp_path`` without blowing memory.

	A fresh connection to the on-disk file is used so we don't deadlock against
	Django's open transaction (notably under ``TestCase``). For in-memory
	databases (tests with ``:memory:`` or ``file::memory:?…``) we fall back to
	``serialize()`` because there is no file to reopen.
	"""
	if db_name == ":memory:" or db_name.startswith("file::memory:") or db_name.startswith("file:memdb"):
		data = source.serialize()
		with Path(tmp_path).open("wb") as fh:
			fh.write(data)
		return

	src_conn = sqlite3.connect(db_name)
	try:
		with sqlite3.connect(tmp_path) as dest:
			src_conn.backup(dest, pages=256, sleep=0.05)
	finally:
		src_conn.close()


def _stream_and_unlink(path: str, audit_context: dict[str, Any]) -> Iterator[bytes]:
	bytes_sent = 0
	completed = False
	try:
		with Path(path).open("rb") as fh:
			while True:
				chunk = fh.read(_BACKUP_STREAM_CHUNK)
				if not chunk:
					completed = True
					break
				bytes_sent += len(chunk)
				yield chunk
	finally:
		_unlink_quiet(path)
		_record_stream_outcome(audit_context, bytes_sent, completed)


def _record_stream_outcome(audit_context: dict[str, Any], bytes_sent: int, completed: bool) -> None:
	username = audit_context.get("username", "?")
	size_bytes = audit_context.get("size_bytes", 0)
	details = {**audit_context, "bytes_streamed": bytes_sent}
	if completed:
		SystemEvent.objects.create(
			level=SystemEvent.Level.INFO,
			source="ops.download_sqlite_backup",
			kind="audit-completed",
			message=f"SQLite backup delivered to {username} ({bytes_sent}/{size_bytes} bytes).",
			details=details,
		)
	else:
		SystemEvent.objects.create(
			level=SystemEvent.Level.WARNING,
			source="ops.download_sqlite_backup",
			kind="audit-aborted",
			message=f"SQLite backup transfer aborted for {username} ({bytes_sent}/{size_bytes} bytes).",
			details=details,
		)


def _unlink_quiet(path: str) -> None:
	with contextlib.suppress(OSError):
		Path(path).unlink()


def _scrub_client_text(value: str, *, max_length: int) -> str:
	text = value.strip()
	for pattern in _SECRET_PATTERNS:
		text = pattern.sub(lambda match: f"{match.group(1)}[redacted]" if match.lastindex else "[redacted]", text)
	return text[:max_length]


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
