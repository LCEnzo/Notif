"""POST /api/v1/health/ingest/: auth, strict validation, the size and item caps, the throttle."""

import io
import json
from typing import Any
from unittest.mock import patch

import pytest
from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework.throttling import ScopedRateThrottle, SimpleRateThrottle

from accounts.models import User
from commons.test_utils import login_client
from commons.utils import create_users
from health.limits import MAX_INGEST_BYTES, MAX_INGEST_ITEMS
from health.models import HealthAggregate, HealthRecord, HealthSource
from health.parsers import BoundedJSONParser, PayloadTooLargeError
from health.tests.support import (
	HEALTH_DATABASES,
	HOUR,
	ms,
	resting_heart_rate_wire,
	sleep_wire,
	steps_wire,
	uid,
	window_wire,
)
from health.views import HealthIngestView
from notif.settings_base import _REST_THROTTLE_RATES

URL = reverse("health-ingest")


def _body(**lists: Any) -> dict[str, Any]:
	return {"coverage_start_ms": None, **lists}


class _SignedInTestCase(TestCase):
	databases = HEALTH_DATABASES
	user: User

	@classmethod
	def setUpTestData(cls):
		cls.user = create_users()[0]

	def setUp(self):
		self.client_ = login_client(APIClient(), self.user.get_username())

	def post(self, body: Any):
		return self.post_raw(json.dumps(body).encode())

	def post_raw(self, raw: bytes):
		return self.client_.post(URL, data=raw, content_type="application/json")


class IngestApiTestCase(_SignedInTestCase):
	def test_a_full_batch_is_stored_under_the_caller(self):
		response = self.post(
			_body(
				steps=[steps_wire(1)],
				resting_heart_rate=[resting_heart_rate_wire(1)],
				sleep_session=[sleep_wire(1)],
				deletions=[{"hc_id": str(uid(999)), "observed_at_ms": ms(2026, 10, 2)}],
				aggregate_windows=[window_wire(ms(2026, 10, 1), 2)],
			)
		)

		assert response.status_code == status.HTTP_200_OK, response.data
		assert {key: value for key, value in response.data.items() if key != "batch_id"} == {
			"records_written": 3,
			"records_ignored": 0,
			"records_deleted": 0,
			"aggregates_written": 2,
			"aggregates_ignored": 0,
		}
		assert set(HealthRecord.objects.values_list("owner_id", flat=True)) == {self.user.pk}

		heart = HealthRecord.objects.get(record_type="resting_heart_rate")
		assert (heart.start_ms, heart.start_offset_s, heart.end_ms) == (ms(2026, 10, 1, 7), 7_200, None)
		assert heart.payload == {"beats_per_minute": 54}
		assert heart.source.device_type == ""

		sleep = HealthRecord.objects.get(record_type="sleep_session")
		# Stages are stored sorted, so a reordered resend is the same version.
		assert [stage["stage"] for stage in sleep.payload["stages"]] == ["light", "deep"]
		assert (sleep.payload["title"], sleep.payload["notes"]) == (None, "")
		assert HealthAggregate.objects.filter(value__isnull=True).count() == 1

	def test_a_resent_batch_writes_nothing(self):
		body = _body(steps=[steps_wire(1)], sleep_session=[sleep_wire(1)])
		self.post(body)
		body["sleep_session"][0]["stages"].reverse()
		response = self.post(body)

		assert (response.data["records_written"], response.data["records_ignored"]) == (0, 2)

	def test_an_empty_batch_is_logged(self):
		response = self.post({"coverage_start_ms": ms(2026, 9, 1)})

		assert response.status_code == status.HTTP_200_OK
		assert response.data["records_written"] == 0

	def test_a_manufacturer_given_as_empty_reads_back_as_null(self):
		self.post(_body(steps=[steps_wire(1, device={"type": "phone", "manufacturer": "", "model": None})]))

		source = HealthSource.objects.get()
		assert (source.device_type, source.device_manufacturer, source.device_model) == ("phone", "", "")

	def test_an_anonymous_caller_is_refused_with_the_session_challenge(self):
		response = APIClient().post(URL, data=json.dumps(_body()), content_type="application/json")

		assert response.status_code == status.HTTP_401_UNAUTHORIZED
		assert response["WWW-Authenticate"] == "Session"

	def test_only_json_is_parsed(self):
		response = self.client_.post(URL, data={"coverage_start_ms": ""})

		assert response.status_code == status.HTTP_415_UNSUPPORTED_MEDIA_TYPE


class IngestValidationTestCase(_SignedInTestCase):
	def assert_refused(self, body: Any) -> dict[str, Any]:
		response = self.post(body)
		assert response.status_code == status.HTTP_400_BAD_REQUEST, response.data
		assert not HealthRecord.objects.exists()
		errors: dict[str, Any] = response.data
		return errors

	def test_an_unsupported_record_type_is_refused_by_name(self):
		errors = self.assert_refused(_body(heart_rate=[{"hc_id": str(uid(1))}], steps=[steps_wire(1)]))

		assert errors == {"heart_rate": ["Unknown field."]}

	def test_unknown_nested_fields_are_refused_with_their_index(self):
		errors = self.assert_refused(_body(steps=[steps_wire(1), steps_wire(2, distance_m=5)]))

		# DRF keys list errors by index; only the failing item appears.
		assert errors == {"steps": {1: {"distance_m": ["Unknown field."]}}}

	def test_bodies_that_are_not_a_json_object_are_refused(self):
		for label, raw in [
			("truncated", b'{"coverage_start_ms": nu'),
			("NaN", b'{"coverage_start_ms": NaN}'),
			("not UTF-8", b'{"coverage_start_ms": null, "steps": ["\xff"]}'),
			("array", b"[]"),
			("scalar", b"7"),
		]:
			with self.subTest(label):
				response = self.post_raw(raw)
				assert response.status_code == status.HTTP_400_BAD_REQUEST

	def test_coverage_start_is_required_but_may_be_null(self):
		assert "coverage_start_ms" in self.assert_refused({"steps": [steps_wire(1)]})

	def test_malformed_records_are_refused(self):
		cases: list[tuple[str, dict[str, Any]]] = [
			("integer as string", steps_wire(1, count="42")),
			("integer as float", steps_wire(1, count=42.0)),
			("integer as bool", steps_wire(1, count=True)),
			("string as integer", steps_wire(1, data_origin=7)),
			("id not a uuid", steps_wire(1, hc_id="not-a-uuid")),
			("id as integer", steps_wire(1, hc_id=5)),
			("end before start", steps_wire(1, end_ms=steps_wire(1)["start_ms"])),
			("offset beyond 18 h", steps_wire(1, start_offset_s=64_801)),
			("time beyond 2100", steps_wire(1, last_modified_ms=4_102_444_800_001)),
			("negative time", steps_wire(1, start_ms=-1)),
			("unknown recording method", steps_wire(1, recording_method="guessed")),
			("unknown device type", steps_wire(1, device={"type": "toaster", "manufacturer": None, "model": None})),
			("device missing a key", steps_wire(1, device={"type": "watch", "manufacturer": None})),
			("missing count", {key: value for key, value in steps_wire(1).items() if key != "count"}),
		]
		for label, record in cases:
			with self.subTest(label):
				self.assert_refused(_body(steps=[record]))

	def test_sleep_stages_must_lie_within_the_session(self):
		session = sleep_wire(1)
		for stage in [
			{"start_ms": session["start_ms"] - 1, "end_ms": session["start_ms"] + HOUR, "stage": "light"},
			{"start_ms": session["start_ms"], "end_ms": session["end_ms"] + 1, "stage": "light"},
			{"start_ms": session["start_ms"] + HOUR, "end_ms": session["start_ms"] + HOUR, "stage": "light"},
			{"start_ms": session["start_ms"], "end_ms": session["start_ms"] + HOUR, "stage": "dozing"},
		]:
			with self.subTest(stage=stage):
				self.assert_refused(_body(sleep_session=[sleep_wire(1, stages=[stage])]))

	def test_sleep_stages_on_the_session_bounds_are_accepted(self):
		session = sleep_wire(1)
		stage = {"start_ms": session["start_ms"], "end_ms": session["end_ms"], "stage": "sleeping"}
		response = self.post(_body(sleep_session=[sleep_wire(1, stages=[stage])]))

		assert response.status_code == status.HTTP_200_OK

	def test_malformed_aggregate_windows_are_refused(self):
		start = ms(2026, 10, 1)
		bucket = {"start_ms": start, "value": 1, "data_origins": []}
		cases: list[tuple[str, dict[str, Any]]] = [
			("start off the hour", window_wire(start + 1, 1, buckets=[])),
			("end before start", window_wire(start, 1, end_ms=start)),
			("over 31 days", window_wire(start, 31 * 24 + 1)),
			("bucket off the hour", window_wire(start, 2, buckets=[{**bucket, "start_ms": start + 60_000}])),
			("bucket outside", window_wire(start, 2, buckets=[{**bucket, "start_ms": start + 2 * HOUR}])),
			("bucket twice", window_wire(start, 2, buckets=[bucket, bucket])),
			("negative value", window_wire(start, 2, buckets=[{**bucket, "value": -1}])),
			("unknown metric", window_wire(start, 2, metric="heart_rate_avg")),
		]
		for label, aggregate_window in cases:
			with self.subTest(label):
				self.assert_refused(_body(aggregate_windows=[aggregate_window]))

	def test_a_31_day_window_is_accepted(self):
		response = self.post(_body(aggregate_windows=[window_wire(ms(2026, 10, 1), 31 * 24)]))

		assert response.status_code == status.HTTP_200_OK
		assert response.data["aggregates_written"] == 31 * 24


class IngestCapTestCase(_SignedInTestCase):
	def test_the_item_cap_counts_every_list_together(self):
		deletions = [{"hc_id": str(uid(n)), "observed_at_ms": 1} for n in range(MAX_INGEST_ITEMS - 2)]
		at_cap = _body(steps=[steps_wire(1)], deletions=deletions, aggregate_windows=[window_wire(0, 1, buckets=[])])
		over_by_a_record = {**at_cap, "steps": [steps_wire(1), steps_wire(2)]}
		over_by_an_hour = {**at_cap, "aggregate_windows": [window_wire(0, 2, buckets=[])]}

		assert self.post(at_cap).status_code == status.HTTP_200_OK
		for label, body in [("record", over_by_a_record), ("window hour", over_by_an_hour)]:
			with self.subTest(label):
				response = self.post(body)
				assert response.status_code == status.HTTP_400_BAD_REQUEST
				assert "at most 5000 items" in str(response.data), response.data

	def test_the_body_cap_is_exact(self):
		at_cap = _padded(MAX_INGEST_BYTES)
		over = _padded(MAX_INGEST_BYTES + 1)

		assert self.post_raw(at_cap).status_code == status.HTTP_200_OK
		response = self.post_raw(over)
		assert response.status_code == status.HTTP_413_REQUEST_ENTITY_TOO_LARGE
		assert response.data == {"detail": f"The request body exceeds {MAX_INGEST_BYTES} bytes."}


def _padded(size: int) -> bytes:
	"""A valid batch of exactly ``size`` bytes; JSON allows the trailing whitespace."""
	body = json.dumps(_body(steps=[steps_wire(n) for n in range(100)])).encode()
	assert len(body) < size
	return body + b" " * (size - len(body))


class _ExplodingStream(io.BytesIO):
	def read(self, size: int | None = -1) -> bytes:
		raise AssertionError("an oversized declared body must be refused unread")


class _Request:
	def __init__(self, content_length: str) -> None:
		self.META = {"CONTENT_LENGTH": content_length}


def test_a_declared_oversize_is_refused_without_reading():
	with pytest.raises(PayloadTooLargeError):
		BoundedJSONParser().parse(_ExplodingStream(), parser_context={"request": _Request(str(MAX_INGEST_BYTES + 1))})


def test_a_body_longer_than_declared_is_still_bounded():
	stream = io.BytesIO(b" " * (MAX_INGEST_BYTES + 10))
	with pytest.raises(PayloadTooLargeError):
		BoundedJSONParser().parse(stream, parser_context={"request": _Request("10")})


class IngestThrottleTestCase(_SignedInTestCase):
	def test_only_the_health_ingest_scope_applies(self):
		assert _REST_THROTTLE_RATES["health_ingest"] == "2000/hour"
		assert HealthIngestView.throttle_classes == [ScopedRateThrottle]
		assert HealthIngestView.throttle_scope == "health_ingest"

	def test_the_scope_throttles_and_the_user_budget_does_not(self):
		client = login_client(APIClient(), self.user.get_username())
		rates = {**_REST_THROTTLE_RATES, "health_ingest": "2/hour", "user": "1/hour"}
		with patch.object(SimpleRateThrottle, "THROTTLE_RATES", rates):
			cache.clear()
			try:
				codes = [
					client.post(URL, data=json.dumps(_body()), content_type="application/json").status_code
					for _ in range(3)
				]
				throttled = client.post(URL, data=json.dumps(_body()), content_type="application/json")
			finally:
				cache.clear()

		assert codes == [status.HTTP_200_OK, status.HTTP_200_OK, status.HTTP_429_TOO_MANY_REQUESTS]
		assert throttled.status_code == status.HTTP_429_TOO_MANY_REQUESTS
		assert int(throttled["Retry-After"]) > 0
