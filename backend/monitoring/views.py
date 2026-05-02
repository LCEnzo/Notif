from typing import cast

from django.db.models import Q
from django.db.models.query import QuerySet
from django.utils import timezone
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.mixins import ListModelMixin, RetrieveModelMixin, UpdateModelMixin
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


class LinkViewSet(OwnerOrAdminQuerysetMixin, ModelViewSet):
	permission_classes = [IsAuthenticated, IsOwnerOrAdmin]
	serializer_class = LinkSerializer

	def get_queryset(self) -> QuerySet[Link]:
		return self._scoped_queryset(Link.objects.all())


class StrategyViewSet(OwnerOrAdminQuerysetMixin, ModelViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = StrategySerializer

	def get_queryset(self) -> QuerySet[Strategy]:
		return self._scoped_queryset(
			Strategy.objects.all(),
			user_filter=lambda qs, u: qs.filter(
				Q(link_set__user=u) | Q(link_set__isnull=True)
			).distinct(),
		)


class NotificationViewSet(ListModelMixin, RetrieveModelMixin, UpdateModelMixin, GenericViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = NotificationSerializer

	def get_queryset(self) -> QuerySet[Notification]:
		user = cast(User, self.request.user)
		queryset = Notification.objects.filter(update__link__user=user)

		status_filter = self.request.query_params.get('status')
		if status_filter:
			queryset = queryset.filter(status=status_filter)

		since = self.request.query_params.get('since')
		if since:
			queryset = queryset.filter(update__created_at__gte=since)

		return queryset.select_related('update')

	def perform_update(self, serializer):
		if serializer.validated_data.get('status') == Notification.Status.READ:
			serializer.save(read_at=timezone.now())
		else:
			serializer.save()

	@action(detail=False, methods=['post'])
	def mark_all_read(self, request: Request) -> Response:
		updated = self.get_queryset().filter(
			status=Notification.Status.UNREAD
		).update(status=Notification.Status.READ, read_at=timezone.now())
		return Response({'marked_read': updated})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def trigger_scrape(request: Request) -> Response:
	user = cast(User, request.user)
	link_id = request.data.get('link_id')
	if link_id:
		try:
			link = Link.objects.get(pk=link_id, user=user)
		except Link.DoesNotExist:
			return Response({'status': 'error', 'message': 'Link not found'}, status=404)

		result = scrape_link(link)
		match result:
			case Ok(value=count):
				return Response({'status': 'ok', 'updates_found': count})
			case Err(error=msg):
				return Response({'status': 'error', 'message': msg}, status=400)
	else:
		results = scrape_all_links(user_id=user.pk)
		summary = {
			str(lid): {'status': 'ok', 'count': r.value} if isinstance(r, Ok)
			else {'status': 'error', 'message': r.error}
			for lid, r in results.items()
		}
		return Response(summary)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_strat_choices(request: Request) -> Response:
	return Response(data=list(STRATEGY_CHOICES))


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request: Request) -> Response:
	"""Health check endpoint — returns 200 if DB is reachable, 503 otherwise."""
	from django.db import connections
	try:
		connections['default'].cursor()
		return Response({'status': 'ok', 'db': 'ok'})
	except Exception:
		return Response({'status': 'error', 'db': 'down'}, status=503)
