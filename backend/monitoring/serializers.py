from rest_framework import serializers  # noqa: F401
from rest_framework.serializers import ModelSerializer

from monitoring.models import Link, Notification, Strategy, Update


class StrategySerializer(ModelSerializer[Strategy]):
	class Meta:
		model = Strategy
		fields = "__all__"


class LinkSerializer(ModelSerializer[Link]):
	class Meta:
		model = Link

		fields = [
			"id",
			"name",
			"url",
			"user",
			"strategy",
			"last_scraped",
			"scrape_interval_minutes",
			"next_scrape_at",
			"scrape_disabled",
			"scrape_failure_count",
			"last_scrape_error",
			"comparison_info",
		]

		read_only_fields = [
			"id",
			"comparison_info",
			"last_scraped",
			"next_scrape_at",
			"scrape_failure_count",
			"last_scrape_error",
		]

		extra_kwargs = {
			"name": {"required": True},
			"url": {"required": True},
			"user": {"required": True},
			"strategy": {"required": True},
		}


class UpdateSerializer(ModelSerializer[Update]):
	class Meta:
		model = Update
		fields = ["id", "link", "title", "description", "item_url", "created_at"]
		read_only_fields = fields


class NotificationSerializer(ModelSerializer[Notification]):
	update = UpdateSerializer(read_only=True)  # type: ignore[assignment]

	class Meta:
		model = Notification
		fields = ["id", "update", "status", "read_at"]
		read_only_fields = ["id", "update", "read_at"]
