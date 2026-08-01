"""DRF authentication for opaque device sessions.

One token, one row, one transport. The interesting decision here is that
rejection is *asymmetric by transport* — see ``authenticate``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser
from drf_spectacular.extensions import OpenApiAuthenticationExtension
from rest_framework import exceptions
from rest_framework.authentication import BaseAuthentication, SessionAuthentication, get_authorization_header
from rest_framework.request import Request

from accounts.device_sessions import session_for_token, touch
from accounts.models import DeviceSession

if TYPE_CHECKING:
	from drf_spectacular.openapi import AutoSchema

AUTH_SCHEME = "Session"


class SessionTokenAuthentication(BaseAuthentication):
	"""Authenticate ``Authorization: Session <token>`` or the session cookie.

	``authenticate_header`` is implemented (returning the scheme) so that a
	failure is a 401 carrying ``WWW-Authenticate: Session`` rather than DRF's
	403 coercion. The client relies on that header to distinguish *our*
	rejection from an edge/proxy 401, and only ends a session on ours.
	"""

	keyword = AUTH_SCHEME

	def authenticate(self, request: Request) -> tuple[AbstractBaseUser, DeviceSession] | None:
		bearer_token = self._bearer_token(request)
		if bearer_token is not None:
			return self._authenticate_bearer(request, bearer_token)

		cookie_token = request.COOKIES.get(settings.SESSION_TOKEN_COOKIE_NAME, "")
		if cookie_token:
			return self._authenticate_cookie(request, cookie_token)

		return None

	def authenticate_header(self, request: Request) -> str:
		return self.keyword

	# ── transports ───────────────────────────────────────────

	def _authenticate_bearer(self, request: Request, raw_token: str) -> tuple[AbstractBaseUser, DeviceSession]:
		"""A dead bearer header is an error, not an absent credential.

		The header is attached deliberately, per request, by a client that
		believes it holds a session — DRF's own TokenAuthentication convention.
		Silently downgrading it to anonymous would turn "your session ended" into
		whatever the endpoint does for strangers.
		"""
		session = session_for_token(raw_token, transport=DeviceSession.Transport.BEARER)
		if session is None:
			raise exceptions.AuthenticationFailed("Invalid or expired session token.")
		# No CSRF check: a bearer header is never attached ambiently by a
		# browser, so there is nothing for a cross-site request to forge with.
		touch(session)
		return (session.user, session)

	def _authenticate_cookie(self, request: Request, raw_token: str) -> tuple[AbstractBaseUser, DeviceSession] | None:
		"""A dead cookie resolves as *no credential*, not as a rejection.

		The browser attaches this cookie to every request under its path,
		including the deliberately anonymous ones — password reset request and
		confirm, registration, the client-event sink, the health probe. Raising
		here would 401 all of them for up to the absolute lifetime after a
		session died, which is exactly when the health probe matters most. The
		alternative, an ``authentication_classes = []`` inventory maintained by
		hand across every anonymous endpoint, is a trap that fails silently the
		first time someone adds an endpoint and forgets.

		Protected endpoints lose nothing: with authenticators present and none
		successful, DRF's permission layer raises ``NotAuthenticated``, which is
		still 401 with ``WWW-Authenticate: Session``.
		"""
		session = session_for_token(raw_token, transport=DeviceSession.Transport.COOKIE)
		if session is None:
			return None

		# A custom authenticator inherits none of SessionAuthentication's CSRF
		# enforcement, so call the very same check explicitly. Only live cookie
		# sessions reach here, which is what makes CSRF failures a property of
		# real mutations rather than of stale cookies.
		SessionAuthentication().enforce_csrf(request)
		touch(session)
		return (session.user, session)

	# ── credential extraction ────────────────────────────────

	def _bearer_token(self, request: Request) -> str | None:
		"""The token from an ``Authorization: Session <token>`` header.

		Returns None when the header is absent or uses another scheme — a
		leftover ``Bearer <jwt>`` from a pre-cutover client is not our
		credential, and treating it as a malformed one would report the wrong
		problem.
		"""
		header = get_authorization_header(request).split()
		if not header or header[0].lower() != self.keyword.lower().encode():
			return None

		if len(header) == 1:
			raise exceptions.AuthenticationFailed("Invalid session header. No credentials provided.")
		if len(header) > 2:
			raise exceptions.AuthenticationFailed("Invalid session header. Token must not contain spaces.")

		try:
			return header[1].decode()
		except UnicodeError as exc:
			raise exceptions.AuthenticationFailed("Invalid session header. Token contains invalid characters.") from exc


class SessionTokenAuthenticationScheme(OpenApiAuthenticationExtension):
	"""Tell drf-spectacular what the two transports look like on the wire.

	Without this the generator emits a warning per view (and the drift check
	fails on warnings), and the published schema would claim the API needs no
	credentials at all.
	"""

	target_class = "accounts.authentication.SessionTokenAuthentication"
	name = ["sessionBearer", "sessionCookie"]

	def get_security_requirement(self, auto_schema: AutoSchema) -> list[dict[str, list[Any]]]:
		# A list is OR, a dict is AND. Transports are mutually exclusive, so a
		# request satisfies exactly one of these — never both.
		return [{"sessionBearer": []}, {"sessionCookie": []}]

	def get_security_definition(self, auto_schema: AutoSchema) -> list[dict[str, Any]]:
		return [
			{
				"type": "http",
				"scheme": AUTH_SCHEME.lower(),
				"description": (
					"Opaque session token issued by POST /api/v1/auth/login/ with transport=bearer, "
					"sent as `Authorization: Session <token>`. Native clients only."
				),
			},
			{
				"type": "apiKey",
				"in": "cookie",
				"name": settings.SESSION_TOKEN_COOKIE_NAME,
				"description": (
					"HttpOnly session cookie set by POST /api/v1/auth/login/ with transport=cookie. "
					"Browser clients only; unsafe methods must also send the csrftoken value in X-CSRFToken."
				),
			},
		]
