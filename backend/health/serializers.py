"""The ingest wire format, validated into ``health.ingest`` types.

Strict where DRF is lenient: undeclared keys are refused (an unsupported record type
is an unknown top-level key), integers must be JSON integers and strings JSON strings.
Each record serializer's ``validate`` returns a ``RecordVersion``, so the request's
``validated_data`` is an ``IngestBatch``.
"""

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any
from uuid import UUID

from django.core.validators import MaxLengthValidator
from rest_framework import serializers
from rest_framework.settings import api_settings

from health import limits
from health.ingest import AggregateBucket, AggregateWindow, Deletion, IngestBatch, RecordVersion, Source
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
	return StrictIntegerField(
		min_value=-limits.MAX_ZONE_OFFSET_S,
		max_value=limits.MAX_ZONE_OFFSET_S,
		allow_null=True,
		help_text="Zone offset in seconds, as HC recorded it; null when HC has none.",
	)


def _list_of(child: _AnySerializer, *, max_length: int, **kwargs: Any) -> serializers.ListSerializer[Any]:
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
	"""HC `Metadata.device`."""

	type = serializers.ChoiceField(choices=DeviceType.choices)
	manufacturer = StrictCharField(max_length=limits.MAX_STRING_LENGTH, allow_null=True, allow_blank=True)
	model = StrictCharField(max_length=limits.MAX_STRING_LENGTH, allow_null=True, allow_blank=True)


class _RecordSerializer(_StrictSerializer):
	hc_id = StrictUUIDField(help_text="HC Metadata.id.")
	data_origin = StrictCharField(max_length=limits.MAX_STRING_LENGTH, help_text="Package name of the writing app.")
	last_modified_ms = _epoch_ms(help_text="HC Metadata.lastModifiedTime, epoch ms.")
	recording_method = serializers.ChoiceField(choices=RecordingMethod.choices)
	device = HealthDeviceSerializer(allow_null=True)

	record_type: RecordType

	def _source(self, attrs: Mapping[str, Any]) -> Source:
		device: Mapping[str, Any] | None = attrs["device"]
		return Source(
			data_origin=attrs["data_origin"],
			recording_method=attrs["recording_method"],
			device_type=device["type"] if device is not None else None,
			# Stored as empty strings, which read back as null; refusing "" instead would stall a sync.
			device_manufacturer=(device["manufacturer"] or None) if device is not None else None,
			device_model=(device["model"] or None) if device is not None else None,
		)


class _IntervalRecordSerializer(_RecordSerializer):
	start_ms = _epoch_ms()
	start_offset_s = _zone_offset_s()
	end_ms = _epoch_ms(help_text="Exclusive; after start_ms.")
	end_offset_s = _zone_offset_s()

	def _version(self, attrs: Mapping[str, Any], payload: Mapping[str, Any]) -> RecordVersion:
		if attrs["end_ms"] <= attrs["start_ms"]:
			raise serializers.ValidationError({"end_ms": ["Must be after start_ms."]})
		return RecordVersion(
			hc_id=attrs["hc_id"],
			record_type=self.record_type,
			source=self._source(attrs),
			start_ms=attrs["start_ms"],
			start_offset_s=attrs["start_offset_s"],
			end_ms=attrs["end_ms"],
			end_offset_s=attrs["end_offset_s"],
			last_modified_ms=attrs["last_modified_ms"],
			payload=payload,
		)


class StepsRecordSerializer(_IntervalRecordSerializer):
	"""HC `StepsRecord`."""

	count = StrictIntegerField(min_value=0, max_value=limits.MAX_STEPS_PER_RECORD)

	record_type = RecordType.STEPS

	def validate(self, attrs: dict[str, Any]) -> RecordVersion:
		return self._version(attrs, {"count": attrs["count"]})


class RestingHeartRateRecordSerializer(_RecordSerializer):
	"""HC `RestingHeartRateRecord`, an instantaneous record."""

	time_ms = _epoch_ms()
	offset_s = _zone_offset_s()
	beats_per_minute = StrictIntegerField(min_value=0, max_value=limits.MAX_BEATS_PER_MINUTE)

	record_type = RecordType.RESTING_HEART_RATE

	def validate(self, attrs: dict[str, Any]) -> RecordVersion:
		return RecordVersion(
			hc_id=attrs["hc_id"],
			record_type=self.record_type,
			source=self._source(attrs),
			start_ms=attrs["time_ms"],
			start_offset_s=attrs["offset_s"],
			end_ms=None,
			end_offset_s=None,
			last_modified_ms=attrs["last_modified_ms"],
			payload={"beats_per_minute": attrs["beats_per_minute"]},
		)


class SleepStageSerializer(_StrictSerializer):
	start_ms = _epoch_ms()
	end_ms = _epoch_ms(help_text="Exclusive; after start_ms.")
	stage = serializers.ChoiceField(choices=SleepStage.choices)


class SleepSessionRecordSerializer(_IntervalRecordSerializer):
	"""HC `SleepSessionRecord`. Stages must lie within the session."""

	title = StrictCharField(max_length=limits.MAX_TEXT_LENGTH, allow_null=True, allow_blank=True)
	notes = StrictCharField(max_length=limits.MAX_TEXT_LENGTH, allow_null=True, allow_blank=True)
	stages = _list_of(SleepStageSerializer(), max_length=limits.MAX_SLEEP_STAGES)

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
			if stage["end_ms"] <= stage["start_ms"]:
				raise serializers.ValidationError({"stages": ["A stage must end after it starts."]})
			if stage["start_ms"] < attrs["start_ms"] or stage["end_ms"] > attrs["end_ms"]:
				raise serializers.ValidationError({"stages": ["Stages must lie within the session."]})
		return self._version(attrs, {"title": attrs["title"], "notes": attrs["notes"], "stages": stages})


class HealthDeletionSerializer(_StrictSerializer):
	hc_id = StrictUUIDField()
	observed_at_ms = _epoch_ms(
		help_text=(
			"When the client learned of the deletion, on the clock HC's last_modified uses. "
			"Removes versions modified at or before it, including ones that arrive later."
		)
	)

	def validate(self, attrs: dict[str, Any]) -> Deletion:
		return Deletion(hc_id=attrs["hc_id"], observed_at_ms=attrs["observed_at_ms"])


class HealthAggregateBucketSerializer(_StrictSerializer):
	start_ms = _epoch_ms(help_text="On a UTC hour; the bucket is one hour long.")
	value = StrictIntegerField(
		min_value=0, max_value=limits.MAX_AGGREGATE_VALUE, help_text="Steps, or milliseconds of sleep."
	)
	data_origins = serializers.ListField(
		child=StrictCharField(max_length=limits.MAX_STRING_LENGTH), max_length=limits.MAX_DATA_ORIGINS
	)


class HealthAggregateWindowSerializer(_StrictSerializer):
	"""One `aggregateGroupByDuration` answer over whole UTC hours."""

	metric = serializers.ChoiceField(choices=AggregateMetric.choices)
	start_ms = _epoch_ms(help_text="On a UTC hour.")
	end_ms = _epoch_ms(help_text="On a UTC hour, exclusive.")
	computed_at_ms = _epoch_ms(help_text="When the client ran the aggregation; the newest answer per hour wins.")
	buckets = _list_of(
		HealthAggregateBucketSerializer(),
		max_length=limits.MAX_WINDOW_HOURS,
		help_text="Hours HC returned. An hour in the window without a bucket had no data.",
	)

	def validate(self, attrs: dict[str, Any]) -> AggregateWindow:
		start_ms: int = attrs["start_ms"]
		end_ms: int = attrs["end_ms"]
		if start_ms % limits.HOUR_MS or end_ms % limits.HOUR_MS:
			raise serializers.ValidationError("start_ms and end_ms must fall on UTC hours.")
		if end_ms <= start_ms:
			raise serializers.ValidationError({"end_ms": ["Must be after start_ms."]})
		if (end_ms - start_ms) // limits.HOUR_MS > limits.MAX_WINDOW_HOURS:
			raise serializers.ValidationError(f"A window spans at most {limits.MAX_WINDOW_HOURS} hours.")

		buckets: list[AggregateBucket] = []
		seen: set[int] = set()
		for bucket in attrs["buckets"]:
			bucket_start: int = bucket["start_ms"]
			if bucket_start % limits.HOUR_MS or not start_ms <= bucket_start < end_ms:
				raise serializers.ValidationError({"buckets": ["Each bucket must start on an hour inside the window."]})
			if bucket_start in seen:
				raise serializers.ValidationError({"buckets": ["Each hour may appear once."]})
			seen.add(bucket_start)
			buckets.append(
				AggregateBucket(
					start_ms=bucket_start,
					value=bucket["value"],
					data_origins=tuple(sorted(set(bucket["data_origins"]))),
				)
			)
		return AggregateWindow(
			metric=AggregateMetric(attrs["metric"]),
			start_ms=start_ms,
			end_ms=end_ms,
			computed_at_ms=attrs["computed_at_ms"],
			buckets=tuple(sorted(buckets, key=lambda bucket: bucket.start_ms)),
		)


_LISTS = ("steps", "resting_heart_rate", "sleep_session", "deletions", "aggregate_windows")


class HealthIngestSerializer(_StrictSerializer):
	"""One batch. Every list is optional; `coverage_start_ms` is required."""

	coverage_start_ms = _epoch_ms(
		allow_null=True,
		help_text=(
			"The earliest instant HC let this client read (first grant minus 30 days without the history "
			"permission); null when the history permission is granted. Silence before it is a gap, not a zero."
		),
	)
	steps = _list_of(StepsRecordSerializer(), max_length=limits.MAX_INGEST_ITEMS, required=False)
	resting_heart_rate = _list_of(
		RestingHeartRateRecordSerializer(), max_length=limits.MAX_INGEST_ITEMS, required=False
	)
	sleep_session = _list_of(SleepSessionRecordSerializer(), max_length=limits.MAX_INGEST_ITEMS, required=False)
	deletions = _list_of(HealthDeletionSerializer(), max_length=limits.MAX_INGEST_ITEMS, required=False)
	aggregate_windows = _list_of(HealthAggregateWindowSerializer(), max_length=limits.MAX_INGEST_ITEMS, required=False)

	def to_internal_value(self, data: Any) -> Any:
		# Refuse an oversized batch before validating thousands of items one by one.
		if isinstance(data, Mapping):
			listed = sum(len(data[key]) for key in _LISTS if isinstance(data.get(key), list))
			if listed > limits.MAX_INGEST_ITEMS:
				raise serializers.ValidationError({api_settings.NON_FIELD_ERRORS_KEY: [_too_many(listed)]})
		return super().to_internal_value(data)

	def validate(self, attrs: dict[str, Any]) -> IngestBatch:
		batch = IngestBatch(
			coverage_start_ms=attrs["coverage_start_ms"],
			records=(*attrs.get("steps", ()), *attrs.get("resting_heart_rate", ()), *attrs.get("sleep_session", ())),
			deletions=tuple(attrs.get("deletions", ())),
			aggregate_windows=tuple(attrs.get("aggregate_windows", ())),
		)
		if batch.item_count > limits.MAX_INGEST_ITEMS:
			raise serializers.ValidationError(_too_many(batch.item_count))
		return batch


def _too_many(count: int) -> str:
	return (
		f"A batch holds at most {limits.MAX_INGEST_ITEMS} items (records, deletions and aggregate-window hours "
		f"together); this one has {count}."
	)


class HealthIngestResponseSerializer(_AnySerializer):
	batch_id = serializers.IntegerField()
	records_written = serializers.IntegerField(help_text="Records created or replaced by a newer version.")
	records_ignored = serializers.IntegerField(help_text="Records not newer than what is stored, or already deleted.")
	records_deleted = serializers.IntegerField(help_text="Stored records removed by this batch's deletions.")
	aggregates_written = serializers.IntegerField(help_text="Aggregate hours created or replaced.")
	aggregates_ignored = serializers.IntegerField(
		help_text="Aggregate hours not newer than what is stored, or before coverage_start_ms."
	)
