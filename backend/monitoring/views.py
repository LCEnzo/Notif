from typing import TYPE_CHECKING, Any, cast

from django.core.paginator import Page
from django.db.models import Q
from django.db.models.query import QuerySet
from django.utils import timezone
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import status as http_status
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.filters import OrderingFilter
from rest_framework.mixins import ListModelMixin, RetrieveModelMixin, UpdateModelMixin
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.serializers import BaseSerializer
from rest_framework.viewsets import GenericViewSet, ModelViewSet

from accounts.models import User
from commons.permissions import IsOwnerOrAdmin, OwnerOrAdminQuerysetMixin
from commons.result import Err, Ok
from monitoring.models import Link, Notification, Strategy
from monitoring.serializers import (
	HealthCheckResponseSerializer,
	LinkSerializer,
	NotificationSerializer,
	StatusCheckResponseSerializer,
	StrategySerializer,
	TriggerScrapeRequestSerializer,
	TriggerScrapeResponseSerializer,
)
from monitoring.services import scrape_all_links, scrape_link
from monitoring.strategies import STRATEGY_CHOICES
from notif.config import settings

if TYPE_CHECKING:
	_LinkModelViewSet = ModelViewSet[Link]
	_StrategyModelViewSet = ModelViewSet[Strategy]
	_NotificationGenericViewSet = GenericViewSet[Notification]
else:
	_LinkModelViewSet = ModelViewSet
	_StrategyModelViewSet = ModelViewSet
	_NotificationGenericViewSet = GenericViewSet


class LinkPagination(PageNumberPagination):
	# Most users will fit under page_size and never see the paginated envelope's
	# next/previous; the FE keeps its UI flat until total exceeds the page.
	page_size = 100
	page_size_query_param = "page_size"
	max_page_size = 500


class LinkViewSet(OwnerOrAdminQuerysetMixin, _LinkModelViewSet):
	permission_classes = [IsAuthenticated, IsOwnerOrAdmin]
	serializer_class = LinkSerializer
	pagination_class = LinkPagination
	filter_backends = [OrderingFilter]
	ordering_fields = ["pk", "last_scraped"]
	ordering = ["-pk"]

	def get_queryset(self) -> QuerySet[Link]:
		# OrderingFilter applies ordering on top of this scoped base queryset.
		return self._scoped_queryset(Link.objects.all())


class StrategyViewSet(OwnerOrAdminQuerysetMixin, _StrategyModelViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = StrategySerializer

	def get_queryset(self) -> QuerySet[Strategy]:
		return self._scoped_queryset(
			Strategy.objects.all(),
			user_filter=lambda qs, u: qs.filter(Q(link_set__user=u) | Q(link_set__isnull=True)).distinct(),
		)

	def perform_destroy(self, instance: Strategy) -> None:
		if instance.link_set.exists():
			raise ValidationError(
				{"detail": "Strategy is still in use by one or more links."},
				code="strategy_in_use",
			)
		instance.delete()


class NotificationPagination(PageNumberPagination):
	page_size = 50
	page_size_query_param = "page_size"
	max_page_size = 200

	def get_paginated_response(self, data: list[dict[str, Any]]) -> Response:
		# unread_count is the user's *global* unread total, not the count within
		# the current filter. The FE needs it to render the badge / enable
		# "mark all read" correctly even when the visible page is all read.
		# self.request and self.page are set by paginate_queryset before this
		# is called; cast to satisfy mypy's nullable view of the attrs.
		request = cast(Request, self.request)
		page = cast(Page[Notification], self.page)
		user = request.user
		assert isinstance(user, User), "authenticated notification pagination requires an application User"
		unread_count = Notification.objects.filter(
			update__link__user=user,
			status=Notification.Status.UNREAD,
		).count()
		return Response(
			{
				"count": page.paginator.count,
				"next": self.get_next_link(),
				"previous": self.get_previous_link(),
				"unread_count": unread_count,
				"results": data,
			}
		)


class NotificationViewSet(ListModelMixin, RetrieveModelMixin, UpdateModelMixin, _NotificationGenericViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = NotificationSerializer
	pagination_class = NotificationPagination
	filter_backends = [OrderingFilter]
	ordering_fields = ["update__created_at", "pk"]
	ordering = ["-update__created_at", "-pk"]
	# Metadata only — get_queryset() below is what runs. Declared so drf-spectacular
	# can derive the model without calling get_queryset() with an AnonymousUser,
	# which asserted and left the {id} path parameter typed as a bare string.
	queryset = Notification.objects.none()

	def get_queryset(self) -> QuerySet[Notification]:
		user = self.request.user
		assert isinstance(user, User), "authenticated notification query requires an application User"
		queryset = Notification.objects.filter(update__link__user=user)

		status_filter = self.request.query_params.get("status")
		if status_filter:
			queryset = queryset.filter(status=status_filter)

		since = self.request.query_params.get("since")
		if since:
			queryset = queryset.filter(update__created_at__gte=since)

		# OrderingFilter applies ordering on top; select_related avoids N+1.
		return queryset.select_related("update")

	def perform_update(self, serializer: BaseSerializer[Notification]) -> None:
		new_status = serializer.validated_data.get("status")
		if new_status == Notification.Status.READ:
			serializer.save(read_at=timezone.now())
		elif new_status == Notification.Status.UNREAD:
			serializer.save(read_at=None)
		else:
			serializer.save()

	@action(detail=False, methods=["post"])
	def mark_all_read(self, request: Request) -> Response:
		updated = (
			self.get_queryset()
			.filter(status=Notification.Status.UNREAD)
			.update(status=Notification.Status.READ, read_at=timezone.now())
		)
		return Response({"marked_read": updated})


def _request_error_message(errors: dict[str, Any]) -> str:
	"""Flatten DRF field errors into the single `message` string this endpoint returns."""
	parts = [f"{field}: {' '.join(str(detail) for detail in details)}" for field, details in errors.items()]
	return "; ".join(parts) or "Invalid request."


@extend_schema(
	request=TriggerScrapeRequestSerializer,
	responses={
		http_status.HTTP_200_OK: TriggerScrapeResponseSerializer,
		http_status.HTTP_400_BAD_REQUEST: TriggerScrapeResponseSerializer,
		http_status.HTTP_404_NOT_FOUND: TriggerScrapeResponseSerializer,
	},
)
@api_view(["POST"])
@permission_classes([IsAuthenticated])
def trigger_scrape(request: Request) -> Response:
	"""Scrape one link, or every link the caller owns.

	Supply ``link_id`` to scrape a single link; omit it to scrape all of them. Both
	modes answer with a top-level ``status``; scrape-all additionally returns a
	``results`` map keyed by stringified link id, whose entries use the same
	``updates_found``/``message`` field names as the single-link response.
	"""
	user = request.user
	assert isinstance(user, User), "authenticated scrape trigger requires an application User"

	# Validated rather than read straight off request.data: a non-numeric link_id
	# used to reach the ORM and raise ValueError (an unhandled 500), and link_id=0
	# was falsy, so it silently scraped *everything*.
	request_serializer = TriggerScrapeRequestSerializer(data=request.data)
	if not request_serializer.is_valid():
		return Response(
			{"status": "error", "message": _request_error_message(request_serializer.errors)},
			status=http_status.HTTP_400_BAD_REQUEST,
		)

	link_id = request_serializer.validated_data.get("link_id")
	if link_id is not None:
		try:
			link = Link.objects.get(pk=link_id, user=user)
		except Link.DoesNotExist:
			return Response(
				{"status": "error", "message": "Link not found"},
				status=http_status.HTTP_404_NOT_FOUND,
			)

		result = scrape_link(link)
		match result:
			case Ok(value=count):
				return Response({"status": "ok", "updates_found": count})
			case Err(error=msg):
				return Response(
					{"status": "error", "message": msg},
					status=http_status.HTTP_400_BAD_REQUEST,
				)
	else:
		results = scrape_all_links(user_id=user.pk)
		return Response(
			{
				"status": "ok",
				"results": {
					str(lid): {"status": "ok", "updates_found": r.value}
					if isinstance(r, Ok)
					else {"status": "error", "message": r.error}
					for lid, r in results.items()
				},
			}
		)


@extend_schema(
	# Renamed from the auto-generated ..._retrieve: this returns a collection.
	operation_id="monitoring_strat_choices_list",
	summary="List available scraping strategy names",
	description=(
		"The strategy class names a Link's Strategy may use, as a flat JSON array. "
		"Values match the StratClsEnum used by the Strategy endpoints."
	),
	responses={
		http_status.HTTP_200_OK: OpenApiResponse(
			# A raw schema dict, not a bare Field: `serializers.ListField(...)` is not
			# resolvable by drf-spectacular, which silently fell back to a free-form
			# *object* while this endpoint returns an *array*.
			response={"type": "array", "items": {"$ref": "#/components/schemas/StratClsEnum"}},
			description="Available strategy class names.",
		),
		http_status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
	},
)
@api_view(["GET"])
@permission_classes([IsAuthenticated])
def get_strat_choices(request: Request) -> Response:
	"""Return the scraping strategy class names a Strategy can be configured with."""
	return Response(data=list(STRATEGY_CHOICES))


@extend_schema(responses={200: HealthCheckResponseSerializer})
@api_view(["GET"])
@permission_classes([AllowAny])
def health_check(request: Request) -> Response:
	"""Liveness probe — returns 200 as long as the process is running.

	No dependency checks. Used by Docker HEALTHCHECK and orchestrators
	to decide whether to restart the container.
	"""
	return Response({"status": "ok"})


@extend_schema(responses={200: StatusCheckResponseSerializer, 503: StatusCheckResponseSerializer})
@api_view(["GET"])
@permission_classes([AllowAny])
def status_check(request: Request) -> Response:
	"""Readiness probe — checks DB connectivity and returns build metadata.

	Returns 200 if all dependencies are healthy, 503 otherwise.
	Used by load balancers and operators to confirm the service can handle traffic
	and to verify which code is deployed.
	"""
	from django.db import connections

	try:
		with connections["default"].cursor() as cursor:
			cursor.execute("SELECT 1")
		db_status = "ok"
		status_code = 200
	except Exception:
		db_status = "down"
		status_code = 503

	return Response(
		{
			"status": "ok" if db_status == "ok" else "error",
			"db": db_status,
			"version": settings.VERSION,
			"commit": settings.GIT_HASH,
			"environment": str(settings.NOTIF_ENV),
		},
		status=status_code,
	)
