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

		fields = [
			'name',
			'url',
			'user',
			'strategy',
			'last_scraped',
			'comparison_info',
		]

		read_only_fields = [
			'comparison_info',
			'last_scraped'
		]

		extra_kwargs = {
			'name': {'required': True},
			'url': {'required': True},
			'user': {'required': True},
			'strategy': {'required': True},
		}
