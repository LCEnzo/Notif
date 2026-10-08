"""A JSON parser that never reads more than a fixed number of bytes.

DRF hands parsers the raw request stream, which bypasses Django's
DATA_UPLOAD_MAX_MEMORY_SIZE, and nothing in front of Django caps bodies.
"""

import io
from collections.abc import Mapping
from typing import IO, Any

from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.parsers import JSONParser

from health.limits import MAX_INGEST_BYTES


class PayloadTooLargeError(APIException):
	status_code = status.HTTP_413_REQUEST_ENTITY_TOO_LARGE
	default_detail = f"The request body exceeds {MAX_INGEST_BYTES} bytes."
	default_code = "payload_too_large"


class BoundedJSONParser(JSONParser):
	max_bytes = MAX_INGEST_BYTES

	def parse(
		self, stream: IO[Any], media_type: str | None = None, parser_context: Mapping[str, Any] | None = None
	) -> Any:
		request = (parser_context or {}).get("request")
		declared = request.META.get("CONTENT_LENGTH") if request is not None else None
		# Refuse a declared oversize without reading it; the bounded read below covers a wrong declaration.
		if declared and declared.isdigit() and int(declared) > self.max_bytes:
			raise PayloadTooLargeError
		body = stream.read(self.max_bytes + 1)
		if len(body) > self.max_bytes:
			raise PayloadTooLargeError
		return super().parse(io.BytesIO(body), media_type, parser_context)
