from django.db.models.query import QuerySet
from rest_framework.permissions import IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from commons.permissions import IsOwnerOrAdmin
from monitoring.models import Link, Strategy
from monitoring.serializers import LinkSerializer, StrategySerializer


class LinkViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated, IsOwnerOrAdmin]
	serializer_class = LinkSerializer

	def get_queryset(self) -> QuerySet[Link]:
		queryset = Link.objects.all()
		user = self.request.user

		user_is_admin = hasattr(user, 'is_staff') and user.is_staff or hasattr(user, 'is_superuser') and user.is_superuser # type: ignore  # noqa: E501
		if user_is_admin:
			return queryset
		
		return queryset.filter(user=user)


class StrategyViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated]
	serializer_class = StrategySerializer

	def get_queryset(self) -> QuerySet[Strategy]:
		queryset = Strategy.objects.all()
		user = self.request.user

		user_is_admin = hasattr(user, 'is_staff') and user.is_staff or hasattr(user, 'is_superuser') and user.is_superuser # type: ignore  # noqa: E501
		if user_is_admin:
			return queryset
		
		return queryset.filter(links__user=user)


