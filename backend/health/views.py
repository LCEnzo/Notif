from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from accounts.models import User
from commons.openapi import ErrorDetailSerializer
from health import limits
from health.ingest import IngestBatch, apply_batch
from health.parsers import BoundedJSONParser
from health.serializers import HealthIngestResponseSerializer, HealthIngestSerializer

_DESCRIPTION = f"""\
Upload one batch of Health Connect data read by the phone. Idempotent: replaying a batch, or \
sending batches in any order, leaves the same rows.

Records are matched by `hc_id` within the caller's account. A record replaces the stored one \
only if its `last_modified_ms` is newer; equal timestamps resolve by content. A deletion \
removes every version of that id modified at or before its `observed_at_ms`, including \
versions that arrive later. Each aggregate hour keeps the answer with the newest \
`computed_at_ms`; an hour inside a window without a bucket is stored as "HC had nothing", \
unless it lies before `coverage_start_ms`.

Limits: a body of at most {limits.MAX_INGEST_BYTES} bytes (413 beyond it) and at most \
{limits.MAX_INGEST_ITEMS} items, counting records, deletions and aggregate-window hours \
together (400 beyond it). Unknown fields anywhere, including unsupported record types, are a \
400. The batch applies atomically. Requests draw on their own `health_ingest` throttle scope, \
not on the general per-user budget.

See docs/architecture/health-ingest.md."""


class HealthIngestView(APIView):
	parser_classes = [BoundedJSONParser]
	# Only the scoped budget: the general per-user one would stall a backfill.
	throttle_classes = [ScopedRateThrottle]
	throttle_scope = "health_ingest"

	@extend_schema(
		operation_id="health_ingest",
		summary="Ingest a batch of Health Connect data",
		description=_DESCRIPTION,
		request=HealthIngestSerializer,
		parameters=[
			OpenApiParameter(
				"Retry-After",
				type=OpenApiTypes.INT,
				location=OpenApiParameter.HEADER,
				response=[status.HTTP_429_TOO_MANY_REQUESTS],
				description="Seconds until the throttle admits another request.",
			),
		],
		responses={
			status.HTTP_200_OK: HealthIngestResponseSerializer,
			status.HTTP_400_BAD_REQUEST: OpenApiResponse(
				description=(
					"The body does not parse, fails validation, holds an unknown field or record type, "
					f"or holds more than {limits.MAX_INGEST_ITEMS} items. Field errors name the list index."
				),
			),
			status.HTTP_413_REQUEST_ENTITY_TOO_LARGE: OpenApiResponse(
				response=ErrorDetailSerializer,
				description=f"The body exceeds {limits.MAX_INGEST_BYTES} bytes.",
			),
			status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
				response=ErrorDetailSerializer,
				description="Over the health_ingest budget; retry after Retry-After seconds.",
			),
		},
	)
	def post(self, request: Request) -> Response:
		user = request.user
		assert isinstance(user, User), "health ingest requires an authenticated application User"
		serializer = HealthIngestSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		batch = serializer.validated_data
		assert isinstance(batch, IngestBatch)
		outcome = apply_batch(owner_id=user.pk, batch=batch)
		return Response(HealthIngestResponseSerializer(outcome).data, status=status.HTTP_200_OK)
