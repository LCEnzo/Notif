"""Schema generation: drf-spectacular's AutoSchema plus the error statuses DRF itself produces."""

from typing import TYPE_CHECKING, Any, override

from drf_spectacular.openapi import AutoSchema
from drf_spectacular.plumbing import ComponentRegistry
from rest_framework import serializers
from rest_framework.permissions import SAFE_METHODS, IsAdminUser

if TYPE_CHECKING:
	_AnySerializer = serializers.Serializer[Any]
else:
	_AnySerializer = serializers.Serializer

_BODY_METHODS = frozenset({"POST", "PUT", "PATCH"})


class ErrorDetailSerializer(_AnySerializer):
	"""DRF's own error body, which every framework-raised 401, 403 and 404 uses."""

	detail = serializers.CharField()


class NotifAutoSchema(AutoSchema):
	"""AutoSchema plus the 400/401/403/404 that DRF's own machinery raises.

	Each is derived from the view, so no view needs a decorator for it; a status the view documents keeps its wording.
	"""

	@override
	def get_operation(
		self,
		path: str,
		path_regex: str,
		path_prefix: str,
		method: str,
		registry: ComponentRegistry,
	) -> dict[str, Any] | None:
		operation = super().get_operation(path, path_regex, path_prefix, method, registry)
		if operation is None:
			return None

		error_detail = self.resolve_serializer(ErrorDetailSerializer, "response").ref
		responses: dict[str, Any] = operation["responses"]
		if self.method in _BODY_METHODS and "400" in responses:
			self._admit_parse_errors(responses["400"], error_detail)
		for code, description in self._framework_errors(operation):
			if code not in responses:
				# A 400 is DRF's {"detail"} or a serializer's per-field errors, so it gets no schema.
				responses[code] = self._error_response(description, None if code == "400" else error_detail)
		operation["responses"] = dict(sorted(responses.items()))
		return operation

	def _framework_errors(self, operation: dict[str, Any]) -> list[tuple[str, str]]:
		parameters: list[dict[str, Any]] = operation.get("parameters", [])
		authenticates = bool(self.view.get_authenticators())
		errors: list[tuple[str, str]] = []

		if self.method in _BODY_METHODS:
			errors.append(("400", "The request body could not be parsed, or failed validation."))

		# Anonymous views included: a dead bearer token is refused, not ignored.
		if authenticates:
			errors.append(("401", "The session token is missing where one is required, or is invalid or expired."))

		forbidden: list[str] = []
		if authenticates and self.method not in SAFE_METHODS:
			forbidden.append("a cookie session sent this write without a valid CSRF token")
		if any(isinstance(permission, IsAdminUser) for permission in self.view.get_permissions()):
			forbidden.append("the caller is not an administrator")
		if forbidden:
			errors.append(("403", f"Forbidden: {', or '.join(forbidden)}."))

		not_found: list[str] = []
		if any(parameter["in"] == "path" for parameter in parameters):
			not_found.append("nothing matches the path parameters")
		# A paginated operation is one drf-spectacular gave the paginator's page parameter.
		paginator = getattr(self.view, "paginator", None)
		query_names = {parameter["name"] for parameter in parameters if parameter["in"] == "query"}
		if paginator is not None and getattr(paginator, "page_query_param", None) in query_names:
			not_found.append("the requested page is past the last one")
		if not_found:
			errors.append(("404", f"Not found: {', or '.join(not_found)}."))

		return errors

	def _error_response(self, description: str, schema: dict[str, Any] | None) -> dict[str, Any]:
		if schema is None:
			return {"description": description}
		return {
			"content": {media_type: {"schema": schema} for media_type in self.map_renderers("media_type")},
			"description": description,
		}

	@staticmethod
	def _admit_parse_errors(response: dict[str, Any], error_detail: dict[str, Any]) -> None:
		# The parser, and for cookie sessions the CSRF check (it reads POST bodies), run
		# before the view, so a body that does not parse is DRF's {"detail"} 400 whatever
		# the view documents. anyOf, not oneOf: the view's shape need not exclude "detail".
		for media in response.get("content", {}).values():
			documented = media.get("schema")
			if documented is None or documented == error_detail:
				continue
			if error_detail in documented.get("anyOf", []):
				continue
			media["schema"] = {"anyOf": [documented, error_detail]}
