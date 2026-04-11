from django.db.models.query import QuerySet
from django.utils import timezone
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.mixins import ListModelMixin, RetrieveModelMixin, UpdateModelMixin
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.viewsets import GenericViewSet, ModelViewSet

from accounts.models import User
from commons.permissions import IsOwnerOrAdmin
from monitoring.models import Link, Notification, Strategy
from monitoring.serializers import LinkSerializer, NotificationSerializer, StrategySerializer
from monitoring.strategies import STRATEGY_CHOICES


class LinkViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated, IsOwnerOrAdmin]
	serializer_class = LinkSerializer

	def get_queryset(self) -> QuerySet[Link]:
		queryset = Link.objects.all()
		user = self.request.user

		if not isinstance(user, User):
			return queryset.none()

		user_is_admin = bool(getattr(user, 'is_staff', False) or getattr(user, 'is_superuser', False))
		if user_is_admin:
			return queryset

		return queryset.filter(user=user)


class StrategyViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = StrategySerializer

	def get_queryset(self) -> QuerySet[Strategy]:
		queryset = Strategy.objects.all()
		user = self.request.user

		if not isinstance(user, User):
			return queryset.none()

		user_is_admin = bool(getattr(user, 'is_staff', False) or getattr(user, 'is_superuser', False))
		if user_is_admin:
			return queryset

		return queryset.filter(link_set__user=user).distinct()


class NotificationViewSet(ListModelMixin, RetrieveModelMixin, UpdateModelMixin, GenericViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = NotificationSerializer

	def get_queryset(self) -> QuerySet[Notification]:
		queryset = Notification.objects.filter(update__link__user=self.request.user)

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


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_strat_choices(request: Request) -> Response:
	return Response(data=list(STRATEGY_CHOICES))
