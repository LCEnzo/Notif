"""A JSON parser that never reads more than a fixed number of bytes.

Not a JSONParser subclass on purpose: DRF buffers a JSONParser's input through
``request.body``, which applies Django's 2.5 MB DATA_UPLOAD_MAX_MEMORY_SIZE as an
unhandled 400. Any other parser gets the raw stream, which this one bounds itself.
"""

import json
from collections.abc import Mapping
from typing import IO, Any, NoReturn

from django.conf import settings
from rest_framework import status
from rest_framework.exceptions import APIException, ParseError
from rest_framework.parsers import BaseParser

from health.limits import MAX_INGEST_BYTES


class PayloadTooLargeError(APIException):
	status_code = status.HTTP_413_REQUEST_ENTITY_TOO_LARGE
	default_detail = f"The request body exceeds {MAX_INGEST_BYTES} bytes."
	default_code = "payload_too_large"


def _refuse_constant(name: str) -> NoReturn:
	raise ValueError(f"{name} is not valid JSON")


class BoundedJSONParser(BaseParser):
	media_type = "application/json"
	max_bytes = MAX_INGEST_BYTES

	def parse(
		self, stream: IO[Any], media_type: str | None = None, parser_context: Mapping[str, Any] | None = None
	) -> Any:
		context = parser_context or {}
		request = context.get("request")
		declared = request.META.get("CONTENT_LENGTH") if request is not None else None
		# Refuse a declared oversize unread; the bounded read covers a wrong declaration.
		if declared and declared.isdigit() and int(declared) > self.max_bytes:
			raise PayloadTooLargeError
		body = stream.read(self.max_bytes + 1)
		if len(body) > self.max_bytes:
			raise PayloadTooLargeError
		try:
			return json.loads(
				body.decode(context.get("encoding", settings.DEFAULT_CHARSET)), parse_constant=_refuse_constant
			)
		except (UnicodeDecodeError, ValueError) as exc:
			raise ParseError(f"JSON parse error - {exc}") from exc
