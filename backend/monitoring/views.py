from typing import cast

from django.core.paginator import Page
from django.db.models import Q
from django.db.models.query import QuerySet
from django.utils import timezone
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.mixins import ListModelMixin, RetrieveModelMixin, UpdateModelMixin
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.viewsets import GenericViewSet, ModelViewSet

from accounts.models import User
from commons.permissions import IsOwnerOrAdmin, OwnerOrAdminQuerysetMixin
from commons.result import Err, Ok
from monitoring.models import Link, Notification, Strategy
from monitoring.serializers import LinkSerializer, NotificationSerializer, StrategySerializer
from monitoring.services import scrape_all_links, scrape_link
from monitoring.strategies import STRATEGY_CHOICES
from notif.config import settings


class LinkPagination(PageNumberPagination):
	# Most users will fit under page_size and never see the paginated envelope's
	# next/previous; the FE keeps its UI flat until total exceeds the page.
	page_size = 100
	page_size_query_param = "page_size"
	max_page_size = 500


class LinkViewSet(OwnerOrAdminQuerysetMixin, ModelViewSet):
	permission_classes = [IsAuthenticated, IsOwnerOrAdmin]
	serializer_class = LinkSerializer
	pagination_class = LinkPagination

	def get_queryset(self) -> QuerySet[Link]:
		# Stable ordering needed once paginated; pk ASC keeps the user's links
		# in the order they were created so the list does not jump on refresh.
		return self._scoped_queryset(Link.objects.all()).order_by("pk")


class StrategyViewSet(OwnerOrAdminQuerysetMixin, ModelViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = StrategySerializer

	def get_queryset(self) -> QuerySet[Strategy]:
		return self._scoped_queryset(
			Strategy.objects.all(),
			user_filter=lambda qs, u: qs.filter(Q(link_set__user=u) | Q(link_set__isnull=True)).distinct(),
		)


class NotificationPagination(PageNumberPagination):
	page_size = 50
	page_size_query_param = "page_size"
	max_page_size = 200

	def get_paginated_response(self, data):
		# unread_count is the user's *global* unread total, not the count within
		# the current filter. The FE needs it to render the badge / enable
		# "mark all read" correctly even when the visible page is all read.
		# self.request and self.page are set by paginate_queryset before this
		# is called; cast to satisfy mypy's nullable view of the attrs.
		request = cast(Request, self.request)
		page = cast(Page, self.page)
		user = cast(User, request.user)
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


class NotificationViewSet(ListModelMixin, RetrieveModelMixin, UpdateModelMixin, GenericViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = NotificationSerializer
	pagination_class = NotificationPagination

	def get_queryset(self) -> QuerySet[Notification]:
		user = cast(User, self.request.user)
		queryset = Notification.objects.filter(update__link__user=user)

		status_filter = self.request.query_params.get("status")
		if status_filter:
			queryset = queryset.filter(status=status_filter)

		since = self.request.query_params.get("since")
		if since:
			queryset = queryset.filter(update__created_at__gte=since)

		# Stable ordering required for paginated results — Update.Meta.ordering
		# is on the related table, so we need an explicit order on the join.
		# pk tiebreaker keeps pages deterministic when timestamps collide.
		return queryset.select_related("update").order_by("-update__created_at", "-pk")

	def perform_update(self, serializer):
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


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def trigger_scrape(request: Request) -> Response:
	user = cast(User, request.user)
	link_id = request.data.get("link_id")
	if link_id:
		try:
			link = Link.objects.get(pk=link_id, user=user)
		except Link.DoesNotExist:
			return Response({"status": "error", "message": "Link not found"}, status=404)

		result = scrape_link(link)
		match result:
			case Ok(value=count):
				return Response({"status": "ok", "updates_found": count})
			case Err(error=msg):
				return Response({"status": "error", "message": msg}, status=400)
	else:
		results = scrape_all_links(user_id=user.pk)
		summary = {
			str(lid): {"status": "ok", "count": r.value}
			if isinstance(r, Ok)
			else {"status": "error", "message": r.error}
			for lid, r in results.items()
		}
		return Response(summary)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def get_strat_choices(request: Request) -> Response:
	return Response(data=list(STRATEGY_CHOICES))


@api_view(["GET"])
@permission_classes([AllowAny])
def health_check(request: Request) -> Response:
	"""Liveness probe — returns 200 as long as the process is running.

	No dependency checks. Used by Docker HEALTHCHECK and orchestrators
	to decide whether to restart the container.
	"""
	return Response({"status": "ok"})


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
