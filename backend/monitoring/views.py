from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.viewsets import ModelViewSet

from commons.permissions import ReadOnly
from monitoring.models import Link, Strategy
from monitoring.serializers import LinkSerializer, StrategySerializer


class LinkViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated, ReadOnly | IsAdminUser]
    queryset = Link.objects.all()
    serializer_class = LinkSerializer


class StrategyViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated, ReadOnly | IsAdminUser]
    queryset = Strategy.objects.all()
    serializer_class = StrategySerializer

