# OpenAPI contract

How `backend/openapi.json` is produced, and what `NotifAutoSchema` (`backend/commons/openapi.py`) adds to drf-spectacular. The plan that introduced the frontend half is [`docs/plan-openapi-fe-contract.md`](../plan-openapi-fe-contract.md) (historical).

## Pipeline

1. **Source.** Serializers and views, plus `@extend_schema` where inference falls short.
2. **Generation.** drf-spectacular walks the URL conf and asks the schema class, `NotifAutoSchema` (`REST_FRAMEWORK["DEFAULT_SCHEMA_CLASS"]`), to describe each operation.
3. **Checked-in schema.** `backend/scripts/check_openapi_drift.py` regenerates with `--validate --fail-on-warn` and diffs the result against `backend/openapi.json`; backend CI runs it. Any drf-spectacular warning fails the check, not only an invalid document. `--write` regenerates the file.
4. **Frontend models.** `frontend/scripts/refresh_contract.py` copies the schema to `frontend/swagger/openapi.json` and runs swagger_dart_code_generator (`build_only_models`) into `frontend/lib/generated/`. Frontend CI reruns it and fails on any diff; its path filter includes `backend/openapi.json`.
5. **Wire checks.** `backend/test_openapi_conformance.py` validates one live round trip against the schema with openapi-core. Schemathesis fuzzing (`backend/test_api_fuzz.py`) arrives with PR #98, open as of 2026-10-06: its `ci` profile runs with the suite, and its only Schemathesis check is that no generated input gets a 5xx; its `deep` profile (weekly or on demand, never gating a merge) runs Schemathesis' default checks, which include status-code and response-schema conformance. That deep check is what an undocumented status trips.

## Why `NotifAutoSchema` exists

Plain `AutoSchema` documents what a view declares: its serializer, or `@extend_schema(responses=...)`. DRF raises several statuses around the view that no view declares: authentication and permission checks in `APIView.initial()`, the CSRF check inside authentication, body parsing on the first read of `request.data`, `get_object()`'s 404, the paginator's 404. The schema therefore under-documented nearly every operation, and a schema-driven client or fuzzer reads each of those statuses as a contract violation.

`NotifAutoSchema.get_operation` runs `AutoSchema`, then adds those statuses, derived from the view. No view needs a decorator for them.

## Rules

Derived in `_framework_errors`:

| Status | Added when | What raises it | Body |
|---|---|---|---|
| 400 | the method is POST, PUT or PATCH | `ParseError` for a body that does not parse; a serializer's `ValidationError` | none, description only |
| 401 | the view has an authenticator (`get_authenticators()` non-empty), `AllowAny` views included | `AuthenticationFailed` for a dead or malformed `Authorization: Session` header, even on anonymous views; `NotAuthenticated` when a permission needs a user and none authenticated | `ErrorDetail` |
| 403 | the view has an authenticator and the method is not GET, HEAD or OPTIONS | CSRF failure on a live cookie session (`SessionTokenAuthentication._authenticate_cookie`) | `ErrorDetail` |
| 403 | a permission is an `IsAdminUser` instance, subclasses included (`ops.views.IsSuperUser`) | `PermissionDenied` | `ErrorDetail` |
| 404 | the operation has a path parameter | `get_object()`'s `Http404` | `ErrorDetail` |
| 404 | the paginator's `page_query_param` is one of the operation's query parameters | `PageNumberPagination` on an invalid page | `ErrorDetail` |

1. Two reasons for one status become one response whose description joins them with "or".
2. A status the view documents itself keeps the view's description and body (login's 401, logout's 403, the device-session endpoints' 401 and 404). Only a view's 400 body is touched, below.
3. It is 401 and not 403 because DRF keeps 401 only when the view's first authenticator returns a `WWW-Authenticate` value; `SessionTokenAuthentication.authenticate_header` returns `Session`.
4. The pagination rule keys on the `page` parameter, not on the paginator: a viewset's non-list actions (`mark_all_read`) have a paginator but no `page`, and cannot 404 on it.
5. Login and logout set `authentication_classes = []`, so no 401 or 403 rule applies; both document their own 400.

## `ErrorDetail` and the 400 `anyOf`

`ErrorDetailSerializer` is DRF's error body, `{"detail": "<message>"}`, published as the `ErrorDetail` component. DRF's default exception handler (the project sets no `EXCEPTION_HANDLER`) renders it for `NotAuthenticated`, `AuthenticationFailed`, `PermissionDenied` (including `CSRF Failed: ...`), `NotFound` and `ParseError`. Views reuse it for the `{"detail"}` 400s they raise themselves (strategy delete, Caddy logs, SQLite backup, the notifications `since` filter). For `/api/` paths no URL pattern matches, such as `/api/v1/monitoring/links/2.5e-42/` (the router's lookup refuses a dot), `notif.views.page_not_found` answers `{"detail": "Not found."}`, so a path-parameter 404 has this body even when DRF never sees the request.

The 400 the schema adds has no body schema: it is either `ParseError`'s `{"detail"}` or a serializer's per-field `{"<field>": ["..."]}`.

Where a POST, PUT or PATCH view documents a 400 with a body of its own, `_admit_parse_errors` widens each media type's schema `S` to `anyOf: [S, ErrorDetail]`, unless `S` is `ErrorDetail` or already lists it. Today that is `change_password` (`ErrorMessage`) and `trigger-scrape` (`TriggerScrapeResponse`). The reason:

1. DRF parses the body lazily, on the first read of `request.data`, and raises `ParseError` there. That read comes before any validation of the view's own, so a body that does not parse gets DRF's `{"detail"}`, whatever the view's own 400 looks like.
2. For a live cookie session the parse happens before the view runs at all: on a POST that carries the CSRF cookie, Django's CSRF check reads `request.POST`, and DRF's `Request.POST` runs the parser. A broken cookie-session POST is a 400 even on a view that never reads its body (`mark_all_read`; the same request with a bearer token gets 200).

`anyOf`, not `oneOf`: `oneOf` rejects a body that matches more than one alternative. Both alternatives are open objects (drf-spectacular emits no `additionalProperties: false`), so a view shape whose required keys a `{"detail"}` body satisfies would match a parse error too, and `oneOf` would fail a correct response. Today's two shapes do not overlap (`ErrorMessage` requires `error`, `TriggerScrapeResponse` requires `status`); `anyOf` keeps a future one from mattering.

## Known limits

1. **Custom refusing permissions are invisible** unless they are `IsAdminUser` instances. A composed permission (`A | B`) is DRF's `OR` object, so it is missed even when it contains `IsAdminUser`. Today `UserViewSet`'s `ReadOnly | IsRequestingThemselves | IsAdminUser` refuses another user's PATCH or DELETE with 403; the status is in the schema through the CSRF rule, but its description names CSRF only. No safe-method operation has an undocumented 403.
2. **The 401 and CSRF-403 rules assume `SessionTokenAuthentication`.** They test for an authenticator, not which one, and hold because it is the only authenticator in the project. An authenticator without `authenticate_header` turns the 401 into a 403; one without CSRF enforcement leaves the CSRF reason documented but unreachable.
3. **Only page-number pagination gets its 404.** The rule looks for `page_query_param`; a `CursorPagination` 404 on a bad cursor would go undocumented. The project has none.
4. **The page 404's description is narrower than the behaviour.** It says "past the last one"; DRF 404s any invalid page, including `?page=0` and negative pages, which the schema allows (`page` is a bare integer).
5. **Only the 400 body is widened.** A view that documents its own 401, 403 or 404 keeps exactly its own body. Today all of those but one are description-only, so their body is unspecified rather than `ErrorDetail`; the exception, `trigger-scrape`'s 404, is the view's own answer, and the operation has no path or page parameter for a framework 404.
6. **Other framework statuses are not documented:** 406 (no renderer for `Accept`), 415 (no parser for `Content-Type`), 429 (throttling, on every view through `DEFAULT_THROTTLE_CLASSES` or the view's own throttles).
7. **The JSON 404 for unmatched `/api/` paths needs `DEBUG` off.** With `DEBUG` on, Django serves its technical 404 page instead of `handler404`.

NOTES.md ("API error format unification") plans to replace DRF's error body; doing so changes `ErrorDetail` and the bodies above.

## Where it is pinned

`backend/test_openapi_schema.py`, against a schema generated in-process:

| Test | Pins |
|---|---|
| `test_framework_error_statuses_are_documented` | which of 400/401/403/404 each rule adds, per operation, with controls (link detail GET/PATCH/DELETE, links list, users list GET/POST, ops events, health, login) |
| `test_framework_errors_carry_drfs_detail_body` | added 401/403/404 bodies are `ErrorDetail`; the added 400 has none |
| `test_a_status_the_view_documents_keeps_its_wording` | login's own 401 is left alone |
| `test_a_view_documented_400_body_also_admits_a_parse_error` | the `anyOf` on `change_password` and `trigger-scrape` |
| `test_view_specific_400s_are_documented`, `test_notification_filters_are_documented` | views' own `ErrorDetail` 400s |

`backend/commons/tests.py`, `FrameworkErrorStatusTestCase`: the runtime DRF behaviour the rules rest on, each test with a control.

| Test | Pins |
|---|---|
| `test_a_page_past_the_last_is_a_404_with_detail` | the pagination 404 and its body |
| `test_the_csrf_check_parses_a_cookie_session_post_body` | a cookie-session POST is parsed before the view; a bearer one is not |
| `test_an_unparseable_body_is_drfs_400_whatever_the_view_answers_with` | the reason for the `anyOf` |
| `test_a_path_the_urlconf_refuses_is_a_json_404_under_the_api` | the JSON 404 for unmatched `/api/` paths |
