from django.db.models.query import QuerySet
from rest_framework.decorators import api_view, permission_classes  # noqa: F401
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from accounts.models import User
from commons.permissions import IsOwnerOrAdmin
from monitoring.models import Link, Strategy
from monitoring.serializers import LinkSerializer, StrategySerializer
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


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_strat_choices(request: Request) -> Response:
	return Response(data=list(STRATEGY_CHOICES))
