from rest_framework import serializers  # noqa: F401
from rest_framework.serializers import ModelSerializer

from monitoring.models import Link, Strategy


class StrategySerializer(ModelSerializer):
    class Meta:
        model = Strategy
        fields = "__all__"


class LinkSerializer(ModelSerializer):
    class Meta:
        model = Link
        fields = "__all__"

