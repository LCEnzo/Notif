"""The ingest wire format, validated into ``health.ingest`` types.

Strict where DRF is lenient: undeclared keys are refused (so is an unsupported record type,
as an unknown top-level key), integers must be JSON integers and strings JSON strings. Each
record serializer's ``validate`` returns a ``RecordVersion``, so ``validated_data`` is an
``IngestBatch``.
"""

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any
from uuid import UUID

from django.core.validators import MaxLengthValidator
from rest_framework import serializers

from health import limits
from health.ingest import HOUR_MS, AggregateBucket, AggregateWindow, Deletion, IngestBatch, RecordVersion, Source
from health.models import AggregateMetric, DeviceType, RecordingMethod, RecordType, SleepStage

if TYPE_CHECKING:
	_AnySerializer = serializers.Serializer[Any]
else:
	_AnySerializer = serializers.Serializer


class StrictIntegerField(serializers.IntegerField):
	def to_internal_value(self, data: Any) -> int:
		if isinstance(data, bool) or not isinstance(data, int):
			self.fail("invalid")
		return super().to_internal_value(data)


class StrictCharField(serializers.CharField):
	def to_internal_value(self, data: Any) -> str:
		if not isinstance(data, str):
			self.fail("invalid")
		return super().to_internal_value(data)


class StrictUUIDField(serializers.UUIDField):
	def to_internal_value(self, data: Any) -> UUID:
		if not isinstance(data, str):
			self.fail("invalid")
		return super().to_internal_value(data)


def _epoch_ms(**kwargs: Any) -> StrictIntegerField:
	return StrictIntegerField(min_value=0, max_value=limits.MAX_EPOCH_MS, **kwargs)


def _zone_offset_s() -> StrictIntegerField:
	bound = limits.MAX_ZONE_OFFSET_S
	return StrictIntegerField(min_value=-bound, max_value=bound, allow_null=True, help_text="Null when HC has none.")


def _text(max_length: int = limits.MAX_STRING_LENGTH, **kwargs: Any) -> StrictCharField:
	return StrictCharField(max_length=max_length, **kwargs)


def _list_of(child: _AnySerializer, max_length: int, **kwargs: Any) -> serializers.ListSerializer[Any]:
	# max_length refuses before validating items; the validator only puts maxItems in the schema.
	return serializers.ListSerializer(
		child=child, max_length=max_length, validators=[MaxLengthValidator(max_length)], **kwargs
	)


class _StrictSerializer(_AnySerializer):
	def to_internal_value(self, data: Any) -> Any:
		if isinstance(data, Mapping):
			unknown = sorted(str(key) for key in data if key not in self.fields)
			if unknown:
				raise serializers.ValidationError(dict.fromkeys(unknown, ["Unknown field."]))
		return super().to_internal_value(data)


class HealthDeviceSerializer(_StrictSerializer):
	"""HC `Metadata.device`. An empty manufacturer or model reads back as null."""

	type = serializers.ChoiceField(choices=DeviceType.choices)
	manufacturer = _text(allow_null=True, allow_blank=True)
	model = _text(allow_null=True, allow_blank=True)


class _RecordSerializer(_StrictSerializer):
	hc_id = StrictUUIDField(help_text="HC Metadata.id.")
	data_origin = _text(help_text="Package name of the writing app.")
	last_modified_ms = _epoch_ms(help_text="HC Metadata.lastModifiedTime; decides which version wins.")
	recording_method = serializers.ChoiceField(choices=RecordingMethod.choices)
	device = HealthDeviceSerializer(allow_null=True)

	record_type: RecordType

	def _version(
		self,
		attrs: Mapping[str, Any],
		payload: Mapping[str, Any],
		start: tuple[int, int | None],
		end: tuple[int | None, int | None] = (None, None),
	) -> RecordVersion:
		"""``start`` and ``end`` are (epoch ms, zone offset s)."""
		if end[0] is not None and end[0] <= start[0]:
			raise serializers.ValidationError({"end_ms": ["Must be after start_ms."]})
		device: Mapping[str, Any] | None = attrs["device"]
		source = Source(
			attrs["data_origin"],
			attrs["recording_method"],
			device["type"] if device else None,
			(device["manufacturer"] or None) if device else None,
			(device["model"] or None) if device else None,
		)
		return RecordVersion(attrs["hc_id"], self.record_type, source, *start, *end, attrs["last_modified_ms"], payload)


class _IntervalRecordSerializer(_RecordSerializer):
	start_ms = _epoch_ms()
	start_offset_s = _zone_offset_s()
	end_ms = _epoch_ms(help_text="Exclusive; after start_ms.")
	end_offset_s = _zone_offset_s()

	def _interval(self, attrs: Mapping[str, Any], payload: Mapping[str, Any]) -> RecordVersion:
		return self._version(
			attrs, payload, (attrs["start_ms"], attrs["start_offset_s"]), (attrs["end_ms"], attrs["end_offset_s"])
		)


class StepsRecordSerializer(_IntervalRecordSerializer):
	"""HC `StepsRecord`."""

	count = StrictIntegerField(min_value=0, max_value=limits.MAX_STEPS_PER_RECORD)
	record_type = RecordType.STEPS

	def validate(self, attrs: dict[str, Any]) -> RecordVersion:
		return self._interval(attrs, {"count": attrs["count"]})


class RestingHeartRateRecordSerializer(_RecordSerializer):
	"""HC `RestingHeartRateRecord`, an instantaneous record."""

	time_ms = _epoch_ms()
	offset_s = _zone_offset_s()
	beats_per_minute = StrictIntegerField(min_value=0, max_value=limits.MAX_BEATS_PER_MINUTE)
	record_type = RecordType.RESTING_HEART_RATE

	def validate(self, attrs: dict[str, Any]) -> RecordVersion:
		payload = {"beats_per_minute": attrs["beats_per_minute"]}
		return self._version(attrs, payload, (attrs["time_ms"], attrs["offset_s"]))


class SleepStageSerializer(_StrictSerializer):
	start_ms = _epoch_ms()
	end_ms = _epoch_ms(help_text="Exclusive; after start_ms.")
	stage = serializers.ChoiceField(choices=SleepStage.choices)


class SleepSessionRecordSerializer(_IntervalRecordSerializer):
	"""HC `SleepSessionRecord`. Stages must lie within the session; they are stored sorted."""

	title = _text(limits.MAX_TEXT_LENGTH, allow_null=True, allow_blank=True)
	notes = _text(limits.MAX_TEXT_LENGTH, allow_null=True, allow_blank=True)
	stages = _list_of(SleepStageSerializer(), limits.MAX_SLEEP_STAGES)
	record_type = RecordType.SLEEP_SESSION

	def validate(self, attrs: dict[str, Any]) -> RecordVersion:
		stages = sorted(
			(
				{"start_ms": stage["start_ms"], "end_ms": stage["end_ms"], "stage": stage["stage"]}
				for stage in attrs["stages"]
			),
			key=lambda stage: (stage["start_ms"], stage["end_ms"], stage["stage"]),
		)
		for stage in stages:
			if not attrs["start_ms"] <= stage["start_ms"] < stage["end_ms"] <= attrs["end_ms"]:
				raise serializers.ValidationError(
					{"stages": ["Each stage must end after it starts, within the session."]}
				)
		return self._interval(attrs, {"title": attrs["title"], "notes": attrs["notes"], "stages": stages})


class HealthDeletionSerializer(_StrictSerializer):
	hc_id = StrictUUIDField()
	observed_at_ms = _epoch_ms(
		help_text=(
			"When the client learned of the deletion, on the clock HC's last_modified uses. "
			"Removes versions modified at or before it, including ones that arrive later."
		)
	)

	def validate(self, attrs: dict[str, Any]) -> Deletion:
		return Deletion(attrs["hc_id"], attrs["observed_at_ms"])


class HealthAggregateBucketSerializer(_StrictSerializer):
	start_ms = _epoch_ms(help_text="On a UTC hour; the bucket is one hour long.")
	value = StrictIntegerField(min_value=0, max_value=limits.MAX_AGGREGATE_VALUE, help_text="Steps, or ms of sleep.")
	data_origins = serializers.ListField(child=_text(), max_length=limits.MAX_DATA_ORIGINS)


class HealthAggregateWindowSerializer(_StrictSerializer):
	"""One `aggregateGroupByDuration` answer over whole UTC hours."""

	metric = serializers.ChoiceField(choices=AggregateMetric.choices)
	start_ms = _epoch_ms(help_text="On a UTC hour.")
	end_ms = _epoch_ms(help_text="On a UTC hour, exclusive.")
	computed_at_ms = _epoch_ms(help_text="When the client ran the aggregation; the newest answer per hour wins.")
	buckets = _list_of(
		HealthAggregateBucketSerializer(),
		limits.MAX_WINDOW_HOURS,
		help_text="Hours HC returned. An hour in the window without a bucket had no data.",
	)

	def validate(self, attrs: dict[str, Any]) -> AggregateWindow:
		start_ms: int = attrs["start_ms"]
		end_ms: int = attrs["end_ms"]
		if start_ms % HOUR_MS or end_ms % HOUR_MS or not 0 < end_ms - start_ms <= limits.MAX_WINDOW_HOURS * HOUR_MS:
			raise serializers.ValidationError(
				f"start_ms and end_ms must fall on UTC hours, 1 to {limits.MAX_WINDOW_HOURS} hours apart."
			)
		starts = [bucket["start_ms"] for bucket in attrs["buckets"]]
		if len(set(starts)) < len(starts) or any(hour % HOUR_MS or not start_ms <= hour < end_ms for hour in starts):
			raise serializers.ValidationError({"buckets": ["Each bucket starts on a distinct hour inside the window."]})
		buckets = sorted(
			(
				AggregateBucket(bucket["start_ms"], bucket["value"], tuple(sorted(set(bucket["data_origins"]))))
				for bucket in attrs["buckets"]
			),
			key=lambda bucket: bucket.start_ms,
		)
		return AggregateWindow(
			AggregateMetric(attrs["metric"]), start_ms, end_ms, attrs["computed_at_ms"], tuple(buckets)
		)


class HealthIngestSerializer(_StrictSerializer):
	"""One batch. Every list is optional; `coverage_start_ms` is required."""

	coverage_start_ms = _epoch_ms(
		allow_null=True,
		help_text=(
			"The earliest instant HC let this client read (first grant minus 30 days without the history "
			"permission); null when the history permission is granted. Silence before it is a gap, not a zero."
		),
	)
	steps = _list_of(StepsRecordSerializer(), limits.MAX_INGEST_ITEMS, required=False)
	resting_heart_rate = _list_of(RestingHeartRateRecordSerializer(), limits.MAX_INGEST_ITEMS, required=False)
	sleep_session = _list_of(SleepSessionRecordSerializer(), limits.MAX_INGEST_ITEMS, required=False)
	deletions = _list_of(HealthDeletionSerializer(), limits.MAX_INGEST_ITEMS, required=False)
	aggregate_windows = _list_of(HealthAggregateWindowSerializer(), limits.MAX_INGEST_ITEMS, required=False)

	def validate(self, attrs: dict[str, Any]) -> IngestBatch:
		batch = IngestBatch(
			coverage_start_ms=attrs["coverage_start_ms"],
			records=(*attrs.get("steps", ()), *attrs.get("resting_heart_rate", ()), *attrs.get("sleep_session", ())),
			deletions=tuple(attrs.get("deletions", ())),
			aggregate_windows=tuple(attrs.get("aggregate_windows", ())),
		)
		if batch.item_count > limits.MAX_INGEST_ITEMS:
			raise serializers.ValidationError(
				f"A batch holds at most {limits.MAX_INGEST_ITEMS} items (records, deletions and aggregate-window "
				f"hours together); this one has {batch.item_count}."
			)
		return batch


class HealthIngestResponseSerializer(_AnySerializer):
	batch_id = serializers.IntegerField()
	records_written = serializers.IntegerField(help_text="Records created, or replaced by a newer version.")
	records_deleted = serializers.IntegerField(help_text="Stored records this batch's deletions removed.")
	aggregates_written = serializers.IntegerField(help_text="Aggregate hours created or replaced.")
