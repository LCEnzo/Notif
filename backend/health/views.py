from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from accounts.models import User
from commons.openapi import ErrorDetailSerializer
from health import limits
from health.ingest import IngestBatch, OwnerGoneError, apply_batch
from health.parsers import BoundedJSONParser
from health.serializers import HealthIngestResponseSerializer, HealthIngestSerializer

_DESCRIPTION = f"""\
Upload one batch of Health Connect data. Applying batches in any order, any number of times, \
leaves the same rows, so a retry is always safe. The rules for versions, deletions, aggregate \
hours and coverage are in docs/architecture/health-ingest.md.

Limits: a body of at most {limits.MAX_INGEST_BYTES} bytes (413 beyond it) and at most \
{limits.MAX_INGEST_ITEMS} items, counting records, deletions and aggregate-window hours \
together (400 beyond it). Unknown fields anywhere, unsupported record types included, are a \
400. The batch applies atomically. Requests draw on their own `health_ingest` throttle scope, \
not on the general per-user budget."""


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
				response=ErrorDetailSerializer, description=f"The body exceeds {limits.MAX_INGEST_BYTES} bytes."
			),
			status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
				response=ErrorDetailSerializer, description="Over the health_ingest budget; retry after Retry-After."
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
		try:
			outcome = apply_batch(user.pk, batch)
		except OwnerGoneError as exc:
			# The account was deleted after this request authenticated; its sessions are gone too.
			raise AuthenticationFailed("The account was deleted or deactivated.") from exc
		return Response(HealthIngestResponseSerializer(outcome).data)
