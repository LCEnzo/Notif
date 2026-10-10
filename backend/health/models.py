"""Health Connect (HC) data: one row per HC record, plus tombstones, hourly aggregates and a batch log.

Times are epoch milliseconds and zone offsets seconds, as HC reports them. The rules
that fill these tables are in docs/architecture/health-ingest.md.
"""

from django.conf import settings
from django.db import models
from django.db.models import F, Q


class RecordType(models.TextChoices):
	STEPS = "steps", "Steps"
	RESTING_HEART_RATE = "resting_heart_rate", "Resting heart rate"
	SLEEP_SESSION = "sleep_session", "Sleep session"


class RecordingMethod(models.TextChoices):
	"""HC ``Metadata.RECORDING_METHOD_*``."""

	UNKNOWN = "unknown", "Unknown"
	ACTIVELY_RECORDED = "actively_recorded", "Actively recorded"
	AUTOMATICALLY_RECORDED = "automatically_recorded", "Automatically recorded"
	MANUAL_ENTRY = "manual_entry", "Manual entry"


class DeviceType(models.TextChoices):
	"""HC ``Device.TYPE_*``."""

	UNKNOWN = "unknown", "Unknown"
	WATCH = "watch", "Watch"
	PHONE = "phone", "Phone"
	SCALE = "scale", "Scale"
	RING = "ring", "Ring"
	HEAD_MOUNTED = "head_mounted", "Head mounted"
	FITNESS_BAND = "fitness_band", "Fitness band"
	CHEST_STRAP = "chest_strap", "Chest strap"
	SMART_DISPLAY = "smart_display", "Smart display"


class SleepStage(models.TextChoices):
	"""HC ``SleepSessionRecord.STAGE_TYPE_*``, stored inside the sleep payload."""

	UNKNOWN = "unknown", "Unknown"
	AWAKE = "awake", "Awake"
	SLEEPING = "sleeping", "Sleeping"
	OUT_OF_BED = "out_of_bed", "Out of bed"
	LIGHT = "light", "Light"
	DEEP = "deep", "Deep"
	REM = "rem", "REM"
	AWAKE_IN_BED = "awake_in_bed", "Awake in bed"


class AggregateMetric(models.TextChoices):
	"""HC aggregates, deduplicated by HC's app priority."""

	STEPS_COUNT_TOTAL = "steps_count_total", "StepsRecord.COUNT_TOTAL (count)"
	SLEEP_DURATION_TOTAL = "sleep_duration_total", "SleepSessionRecord.SLEEP_DURATION_TOTAL (ms)"


class HealthSource(models.Model):
	"""Who wrote a record and on what, stored once and shared by records (about 90 bytes a record saved).

	Empty strings stand for HC's nulls, because SQLite treats NULLs as distinct in a
	unique constraint. An empty ``device_type`` means HC reported no device.
	"""

	data_origin = models.CharField(max_length=255)
	recording_method = models.CharField(max_length=32, choices=RecordingMethod.choices)
	device_type = models.CharField(max_length=32, choices=DeviceType.choices, blank=True)
	device_manufacturer = models.CharField(max_length=255, blank=True)
	device_model = models.CharField(max_length=255, blank=True)

	class Meta:
		constraints = [
			models.UniqueConstraint(
				fields=["data_origin", "recording_method", "device_type", "device_manufacturer", "device_model"],
				name="health_source_unique",
			),
			models.CheckConstraint(
				condition=~Q(device_type="") | (Q(device_manufacturer="") & Q(device_model="")),
				name="health_source_no_device_details_without_device",
			),
		]

	def __str__(self) -> str:
		return f"{self.data_origin} ({self.device_type or 'no device'})"


# Owner foreign keys carry no index of their own: each table's unique constraint or index starts with owner.


class HealthRecord(models.Model):
	"""The current version of one HC record. ``end_ms`` is null for instantaneous types."""

	owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+", db_index=False)
	hc_id = models.UUIDField()
	record_type = models.CharField(max_length=32, choices=RecordType.choices)
	# Sources are never deleted, so nothing looks records up by source.
	source = models.ForeignKey(HealthSource, on_delete=models.PROTECT, related_name="+", db_index=False)
	start_ms = models.BigIntegerField()
	start_offset_s = models.IntegerField(null=True)
	end_ms = models.BigIntegerField(null=True)
	end_offset_s = models.IntegerField(null=True)
	last_modified_ms = models.BigIntegerField()
	payload = models.JSONField()

	class Meta:
		constraints = [
			models.UniqueConstraint(fields=["owner", "hc_id"], name="health_record_owner_hc_id_unique"),
			models.CheckConstraint(
				condition=Q(end_ms__isnull=True) | Q(end_ms__gt=F("start_ms")), name="health_record_end_after_start"
			),
		]
		indexes = [models.Index(fields=["owner", "record_type", "start_ms"], name="health_record_type_start")]

	def __str__(self) -> str:
		return f"{self.record_type} {self.hc_id}"


class HealthDeletion(models.Model):
	"""A tombstone: versions modified at or before ``observed_at_ms`` stay deleted, however late they arrive."""

	owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+", db_index=False)
	hc_id = models.UUIDField()
	observed_at_ms = models.BigIntegerField()

	class Meta:
		constraints = [models.UniqueConstraint(fields=["owner", "hc_id"], name="health_deletion_owner_hc_id_unique")]

	def __str__(self) -> str:
		return f"deleted {self.hc_id}"


class HealthAggregate(models.Model):
	"""HC's answer for one metric and UTC hour. A null ``value`` means HC had nothing (a zero); no row means never asked."""

	owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+", db_index=False)
	metric = models.CharField(max_length=32, choices=AggregateMetric.choices)
	bucket_start_ms = models.BigIntegerField()
	value = models.BigIntegerField(null=True)
	data_origins = models.JSONField(default=list)
	computed_at_ms = models.BigIntegerField()

	class Meta:
		constraints = [
			models.UniqueConstraint(
				fields=["owner", "metric", "bucket_start_ms"], name="health_aggregate_owner_metric_bucket_unique"
			),
		]

	def __str__(self) -> str:
		return f"{self.metric} @ {self.bucket_start_ms}"


class HealthIngestBatch(models.Model):
	"""One accepted batch. ``coverage_start_ms`` is the earliest instant HC let the phone read (null: no limit)."""

	owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+", db_index=False)
	received_at = models.DateTimeField(auto_now_add=True)
	coverage_start_ms = models.BigIntegerField(null=True)
	record_count = models.PositiveIntegerField()
	deletion_count = models.PositiveIntegerField()
	aggregate_hour_count = models.PositiveIntegerField()

	class Meta:
		indexes = [models.Index(fields=["owner", "received_at"], name="health_batch_owner_received")]

	def __str__(self) -> str:
		return f"batch {self.pk}"
