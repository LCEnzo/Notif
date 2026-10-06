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

# Methods whose request carries a body that DRF parses.
_BODY_METHODS = frozenset({"POST", "PUT", "PATCH"})


class ErrorDetailSerializer(_AnySerializer):
	"""DRF's own error body, which every framework-raised 401, 403 and 404 uses."""

	detail = serializers.CharField()


class NotifAutoSchema(AutoSchema):
	"""AutoSchema that also documents the error statuses DRF's own machinery produces.

	drf-spectacular documents success responses only, unless a view lists more
	with @extend_schema. Each status added here comes from DRF machinery that
	runs on every view using it, so it is derived from the view rather than
	repeated by hand on each one.

	400 on POST, PUT and PATCH: the body may not parse, or may fail validation.

	401 on any view with an authenticator. A dead or malformed bearer token is
	refused even where anonymous callers are welcome, and a protected view
	refuses a missing credential.

	403 on unsafe methods of a view with an authenticator, which refuses a live
	cookie session sent without a valid CSRF token; and on views gated on
	IsAdminUser (IsSuperUser included), which refuse every other caller.

	404 on a path parameter, which an object lookup can miss, and on a
	paginated list, which refuses a page past the last one.

	A status the view documents itself keeps the view's wording. The parser
	runs before the view, and for cookie sessions so does the CSRF check, which
	reads POST bodies too; so a body that does not parse is DRF's 400
	``{"detail": ...}`` whatever 400 body the view documents, and that body is
	widened to accept either shape.
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
				# A 400's body is either DRF's {"detail"} or a serializer's
				# per-field errors, so it is described rather than given a schema.
				responses[code] = self._error_response(description, None if code == "400" else error_detail)
		operation["responses"] = dict(sorted(responses.items()))
		return operation

	def _framework_errors(self, operation: dict[str, Any]) -> list[tuple[str, str]]:
		parameters: list[dict[str, Any]] = operation.get("parameters", [])
		authenticates = bool(self.view.get_authenticators())
		errors: list[tuple[str, str]] = []

		if self.method in _BODY_METHODS:
			errors.append(("400", "The request body could not be parsed, or failed validation."))

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
		# anyOf rather than oneOf: a view's own 400 schema need not exclude a
		# "detail" key, and either shape matching is all a client can rely on.
		for media in response.get("content", {}).values():
			documented = media.get("schema")
			if documented is None or documented == error_detail:
				continue
			if error_detail in documented.get("anyOf", []):
				continue
			media["schema"] = {"anyOf": [documented, error_detail]}
