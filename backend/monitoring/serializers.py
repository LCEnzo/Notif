from typing import TYPE_CHECKING, Any

from rest_framework import serializers
from rest_framework.serializers import ModelSerializer

from monitoring.models import Link, Notification, Strategy, Update

if TYPE_CHECKING:
	_StrategyModelSerializer = ModelSerializer[Strategy]
	_LinkModelSerializer = ModelSerializer[Link]
	_UpdateModelSerializer = ModelSerializer[Update]
	_NotificationModelSerializer = ModelSerializer[Notification]
	_AnySerializer = serializers.Serializer[Any]
else:
	_StrategyModelSerializer = ModelSerializer
	_LinkModelSerializer = ModelSerializer
	_UpdateModelSerializer = ModelSerializer
	_NotificationModelSerializer = ModelSerializer
	_AnySerializer = serializers.Serializer


class StrategySerializer(_StrategyModelSerializer):
	class Meta:
		model = Strategy
		fields = "__all__"


class LinkSerializer(_LinkModelSerializer):
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


class UpdateSerializer(_UpdateModelSerializer):
	class Meta:
		model = Update
		fields = ["id", "link", "title", "description", "item_url", "created_at"]
		read_only_fields = fields


class NotificationSerializer(_NotificationModelSerializer):
	update = UpdateSerializer(read_only=True)  # type: ignore[assignment]

	class Meta:
		model = Notification
		fields = ["id", "update", "status", "read_at"]
		read_only_fields = ["id", "update", "read_at"]


class TriggerScrapeRequestSerializer(_AnySerializer):
	link_id = serializers.IntegerField(min_value=1, required=False)


class TriggerScrapeLinkResultSerializer(_AnySerializer):
	"""Outcome for one link inside a scrape-all response."""

	status = serializers.CharField(help_text='"ok" or "error".')
	updates_found = serializers.IntegerField(required=False, help_text='Present when status is "ok".')
	message = serializers.CharField(required=False, help_text='Present when status is "error".')


class TriggerScrapeResponseSerializer(_AnySerializer):
	"""The single response shape for POST /monitoring/trigger-scrape/.

	Every response, at every status code, carries ``status``. A single-link call
	(``link_id`` supplied) adds ``updates_found`` on success or ``message`` on
	failure. A scrape-all call adds ``results``: a ``{"<link_id>": {...}}`` map whose
	entries reuse the same field names.

	This replaces the previous pair of serializers. The two request modes genuinely
	return different payloads, and drf-spectacular 0.29 cannot express that as a
	union without a discriminator — ``PolymorphicProxySerializer`` breaks client
	generation — so the honest declaration is one component whose only guaranteed
	member is ``status``, which is exactly what the endpoint promises.
	"""

	status = serializers.CharField(help_text='"ok" or "error".')
	updates_found = serializers.IntegerField(
		required=False,
		help_text="Single-link success only: number of updates created.",
	)
	message = serializers.CharField(required=False, help_text="Error detail.")
	results = serializers.DictField(
		child=TriggerScrapeLinkResultSerializer(),
		required=False,
		help_text="Scrape-all only: per-link outcome keyed by stringified link id.",
	)


class HealthCheckResponseSerializer(_AnySerializer):
	status = serializers.CharField()


class StatusCheckResponseSerializer(_AnySerializer):
	status = serializers.CharField()
	db = serializers.CharField()
	version = serializers.CharField()
	commit = serializers.CharField()
	environment = serializers.CharField()
