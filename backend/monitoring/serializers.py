from typing import TYPE_CHECKING, Any
from urllib.parse import urlsplit

from django.db.models import QuerySet
from rest_framework import serializers
from rest_framework.serializers import ModelSerializer

from monitoring import safe_fetch
from monitoring.models import Link, Notification, Strategy, Update
from monitoring.safe_fetch import NonPublicHostError

if TYPE_CHECKING:
	_StrategyModelSerializer = ModelSerializer[Strategy]
	_LinkModelSerializer = ModelSerializer[Link]
	_UpdateModelSerializer = ModelSerializer[Update]
	_NotificationModelSerializer = ModelSerializer[Notification]
	_AnySerializer = serializers.Serializer[Any]
	_StrategyRelatedField = serializers.PrimaryKeyRelatedField[Strategy]
else:
	_StrategyModelSerializer = ModelSerializer
	_LinkModelSerializer = ModelSerializer
	_UpdateModelSerializer = ModelSerializer
	_NotificationModelSerializer = ModelSerializer
	_AnySerializer = serializers.Serializer
	_StrategyRelatedField = serializers.PrimaryKeyRelatedField


class StrategySerializer(_StrategyModelSerializer):
	class Meta:
		model = Strategy
		# Explicit field list (not "__all__"): ownership is server-assigned and
		# read-only, and `data` may hold third-party credentials, so the field set
		# is stated deliberately rather than derived.
		fields = ["id", "user", "strat_cls", "data"]
		read_only_fields = ["id", "user"]


class OwnedStrategyField(_StrategyRelatedField):
	"""A strategy reference scoped to the requester's own strategies.

	get_queryset is DRF's per-request extension point for related-field
	validation, so a link can only ever reference a strategy its owner owns — a
	caller cannot point their link at (and thereby exercise) another user's
	strategy and stored credentials.
	"""

	def get_queryset(self) -> QuerySet[Strategy]:
		queryset = super().get_queryset()
		assert queryset is not None, "OwnedStrategyField is always constructed with a base queryset"
		request = self.context.get("request")
		user = getattr(request, "user", None)
		if user is None or user.is_anonymous:
			return queryset.none()
		if user.is_staff or user.is_superuser:
			return queryset
		return queryset.filter(user=user)


class LinkSerializer(_LinkModelSerializer):
	strategy = OwnedStrategyField(queryset=Strategy.objects.all(), allow_null=True)

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
			"user",
			"comparison_info",
			"last_scraped",
			"next_scrape_at",
			"scrape_failure_count",
			"last_scrape_error",
		]

		extra_kwargs = {
			"name": {"required": True},
			"url": {"required": True},
			"strategy": {"required": True},
		}

	def validate_url(self, value: str) -> str:
		"""Reject URLs whose host resolves to a non-public address, at write time.

		This resolves the host — a real, blocking DNS lookup on the request path —
		so a bad target is refused when the Link is saved, with an error the client
		can act on. It is not the authoritative check: ``safe_fetch`` re-resolves
		and pins every hop at scrape time, because the answer can change between
		write and fetch.

		Looked up on the module (not bound at import) so tests can patch
		``safe_fetch.resolve_public_host`` and so a stale binding can never
		survive a re-import order change.
		"""
		try:
			safe_fetch.resolve_public_host(urlsplit(value).hostname or "")
		except NonPublicHostError as exc:
			raise serializers.ValidationError(str(exc)) from exc
		return value


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
