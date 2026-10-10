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
from health.tests.support import HOUR, ms, resting_heart_rate_wire, sleep_wire, steps_wire, uid, window_wire
from health.views import HealthIngestView
from notif.settings_base import _REST_THROTTLE_RATES

URL = reverse("health-ingest")


def _body(**lists: Any) -> dict[str, Any]:
	return {"coverage_start_ms": None, **lists}


class _SignedInTestCase(TestCase):
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

	def assert_refused(self, body: Any) -> dict[str, Any]:
		response = self.post(body)
		assert response.status_code == status.HTTP_400_BAD_REQUEST, response.data
		assert not HealthRecord.objects.exists()
		errors: dict[str, Any] = response.data
		return errors


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
			"records_deleted": 0,
			"aggregates_written": 2,
		}
		assert set(HealthRecord.objects.values_list("owner_id", flat=True)) == {self.user.pk}
		heart = HealthRecord.objects.get(record_type="resting_heart_rate")
		assert (heart.start_ms, heart.start_offset_s, heart.end_ms, heart.source.device_type) == (
			ms(2026, 10, 1, 7),
			7_200,
			None,
			"",
		)
		sleep = HealthRecord.objects.get(record_type="sleep_session")
		assert [stage["stage"] for stage in sleep.payload["stages"]] == ["light", "deep"]
		assert HealthAggregate.objects.filter(value__isnull=True).count() == 1

	def test_a_resent_batch_with_reordered_stages_writes_nothing(self):
		body = _body(steps=[steps_wire(1)], sleep_session=[sleep_wire(1)])
		self.post(body)
		body["sleep_session"][0]["stages"].reverse()

		assert self.post(body).data["records_written"] == 0

	def test_an_empty_manufacturer_is_stored_as_none(self):
		self.post(_body(steps=[steps_wire(1, device={"type": "phone", "manufacturer": "", "model": None})]))

		source = HealthSource.objects.get()
		assert (source.device_type, source.device_manufacturer, source.device_model) == ("phone", "", "")

	def test_an_anonymous_caller_gets_the_session_challenge(self):
		response = APIClient().post(URL, data=json.dumps(_body()), content_type="application/json")

		assert response.status_code == status.HTTP_401_UNAUTHORIZED
		assert response["WWW-Authenticate"] == "Session"

	def test_only_json_is_parsed(self):
		assert self.client_.post(URL, data={"coverage_start_ms": ""}).status_code == 415


class IngestValidationTestCase(_SignedInTestCase):
	def test_unknown_record_types_and_fields_are_refused_by_name(self):
		assert self.assert_refused(_body(heart_rate=[{}], steps=[steps_wire(1)])) == {"heart_rate": ["Unknown field."]}
		# DRF keys list errors by index; only the failing item appears.
		errors = self.assert_refused(_body(steps=[steps_wire(1), steps_wire(2, distance_m=5)]))
		assert errors == {"steps": {1: {"distance_m": ["Unknown field."]}}}

	def test_bodies_that_are_not_a_json_object_are_refused(self):
		for raw in [b'{"coverage_start_ms": nu', b'{"coverage_start_ms": NaN}', b'{"steps": ["\xff"]}', b"[]", b"7"]:
			with self.subTest(raw=raw):
				assert self.post_raw(raw).status_code == status.HTTP_400_BAD_REQUEST

	def test_coverage_start_is_required(self):
		assert "coverage_start_ms" in self.assert_refused({"steps": [steps_wire(1)]})

	def test_malformed_records_are_refused(self):
		cases: dict[str, dict[str, Any]] = {
			"integer as string": steps_wire(1, count="42"),
			"integer as float": steps_wire(1, count=42.0),
			"integer as bool": steps_wire(1, count=True),
			"string as integer": steps_wire(1, data_origin=7),
			"id not a uuid": steps_wire(1, hc_id="not-a-uuid"),
			"id as integer": steps_wire(1, hc_id=5),
			"end at start": steps_wire(1, end_ms=steps_wire(1)["start_ms"]),
			"offset beyond 18 h": steps_wire(1, start_offset_s=64_801),
			"time beyond 2100": steps_wire(1, last_modified_ms=4_102_444_800_001),
			"negative time": steps_wire(1, start_ms=-1),
			"unknown recording method": steps_wire(1, recording_method="guessed"),
			"unknown device type": steps_wire(1, device={"type": "toaster", "manufacturer": None, "model": None}),
			"device missing a key": steps_wire(1, device={"type": "watch", "manufacturer": None}),
			"missing count": {key: value for key, value in steps_wire(1).items() if key != "count"},
		}
		for label, record in cases.items():
			with self.subTest(label):
				self.assert_refused(_body(steps=[record]))

	def test_sleep_stages_must_lie_within_the_session(self):
		start, end = sleep_wire(1)["start_ms"], sleep_wire(1)["end_ms"]
		for stage_start, stage_end, stage in [
			(start - 1, start + HOUR, "light"),
			(start, end + 1, "light"),
			(start + HOUR, start + HOUR, "light"),
			(start, start + HOUR, "dozing"),
		]:
			with self.subTest(stage=(stage_start, stage_end, stage)):
				stages = [{"start_ms": stage_start, "end_ms": stage_end, "stage": stage}]
				self.assert_refused(_body(sleep_session=[sleep_wire(1, stages=stages)]))
		on_the_bounds = [{"start_ms": start, "end_ms": end, "stage": "sleeping"}]
		assert self.post(_body(sleep_session=[sleep_wire(1, stages=on_the_bounds)])).status_code == 200

	def test_malformed_aggregate_windows_are_refused(self):
		start = ms(2026, 10, 1)
		bucket = {"start_ms": start, "value": 1, "data_origins": []}
		cases: dict[str, dict[str, Any]] = {
			"start off the hour": window_wire(start + 1, 1, buckets=[]),
			"end at start": window_wire(start, 1, end_ms=start),
			"over 31 days": window_wire(start, 31 * 24 + 1),
			"bucket off the hour": window_wire(start, 2, buckets=[{**bucket, "start_ms": start + 60_000}]),
			"bucket outside": window_wire(start, 2, buckets=[{**bucket, "start_ms": start + 2 * HOUR}]),
			"bucket twice": window_wire(start, 2, buckets=[bucket, bucket]),
			"negative value": window_wire(start, 2, buckets=[{**bucket, "value": -1}]),
			"unknown metric": window_wire(start, 2, metric="heart_rate_avg"),
		}
		for label, aggregate_window in cases.items():
			with self.subTest(label):
				self.assert_refused(_body(aggregate_windows=[aggregate_window]))
		response = self.post(_body(aggregate_windows=[window_wire(start, 31 * 24)]))
		assert response.data["aggregates_written"] == 31 * 24


class IngestCapTestCase(_SignedInTestCase):
	def test_one_item_over_the_cap_is_refused(self):
		deletions = [{"hc_id": str(uid(n)), "observed_at_ms": 1} for n in range(MAX_INGEST_ITEMS)]
		errors = self.assert_refused(_body(steps=[steps_wire(1)], deletions=deletions))

		assert "at most 5000 items" in str(errors)

	def test_the_body_cap_is_exact(self):
		body = json.dumps(_body(steps=[steps_wire(n) for n in range(100)])).encode()

		# JSON allows the trailing whitespace.
		assert self.post_raw(body + b" " * (MAX_INGEST_BYTES - len(body))).status_code == status.HTTP_200_OK
		response = self.post_raw(body + b" " * (MAX_INGEST_BYTES + 1 - len(body)))
		assert response.status_code == status.HTTP_413_REQUEST_ENTITY_TOO_LARGE
		assert response.data == {"detail": f"The request body exceeds {MAX_INGEST_BYTES} bytes."}


class _Request:
	def __init__(self, content_length: str) -> None:
		self.META = {"CONTENT_LENGTH": content_length}


class _Unreadable(io.BytesIO):
	def read(self, size: int | None = -1) -> bytes:
		raise AssertionError("an oversized declared body must be refused unread")


@pytest.mark.parametrize(
	("stream", "declared"),
	[(_Unreadable(), str(MAX_INGEST_BYTES + 1)), (io.BytesIO(b" " * (MAX_INGEST_BYTES + 10)), "10")],
	ids=["declared oversize, unread", "longer than declared, still bounded"],
)
def test_the_parser_never_reads_past_the_cap(stream: io.BytesIO, declared: str):
	with pytest.raises(PayloadTooLargeError):
		BoundedJSONParser().parse(stream, parser_context={"request": _Request(declared)})


class IngestThrottleTestCase(_SignedInTestCase):
	def test_only_the_health_ingest_scope_applies(self):
		assert _REST_THROTTLE_RATES["health_ingest"] == "2000/hour"
		assert (HealthIngestView.throttle_classes, HealthIngestView.throttle_scope) == (
			[ScopedRateThrottle],
			"health_ingest",
		)
		rates = {**_REST_THROTTLE_RATES, "health_ingest": "2/hour", "user": "1/hour"}
		with patch.object(SimpleRateThrottle, "THROTTLE_RATES", rates):
			cache.clear()
			try:
				responses = [self.post(_body()) for _ in range(3)]
			finally:
				cache.clear()

		assert [response.status_code for response in responses] == [200, 200, 429]
		assert int(responses[2]["Retry-After"]) > 0
