import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/commons/browser_cookies.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/session_store.dart';

const String builtinApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

/// Resolve the built-in API URL into a usable request base.
///
/// Production web builds ship a relative `API_URL` (`/api/v1`): the app is
/// served and backed by one origin, and a relative URL keeps the image free of
/// a baked-in hostname. Relative means same-origin by construction, so on web
/// it resolves against the serving [page] here — before
/// [describeUnsupportedOrigin], which deliberately keeps requiring absolute
/// http(s) URLs for anything entered by hand. Native builds have no page
/// origin: the value passes through unchanged and the absolute-URL validation
/// applies to it as-is.
String resolveBuiltinApiUrl(
  String builtin, {
  required bool isWeb,
  required Uri page,
}) {
  if (!isWeb) return builtin;
  final parsed = Uri.tryParse(builtin);
  if (parsed == null || parsed.hasScheme) return builtin;
  return page.resolveUri(parsed).toString();
}

String get _effectiveBuiltinApiUrl =>
    resolveBuiltinApiUrl(builtinApiUrl, isWeb: kIsWeb, page: Uri.base);

const Duration connectTimeout = Duration(seconds: 10);
const Duration receiveTimeout = Duration(seconds: 15);

/// The scheme the backend challenges with, and the one we answer it with.
const String sessionAuthScheme = 'Session';

/// Django's readable CSRF cookie and the header it expects it echoed in.
const String csrfCookieName = 'csrftoken';
const String csrfHeaderName = 'X-CSRFToken';

const Map<String, String> jsonHeaders = {'Content-Type': 'application/json'};

const Set<String> _csrfSafeMethods = {'GET', 'HEAD', 'OPTIONS', 'TRACE'};

/// Shared Dio instance — connection pooling happens here.
final Dio _dio =
    Dio(
        BaseOptions(
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        ),
      )
      ..interceptors.addAll([
        if (kDebugMode)
          LogInterceptor(
            requestHeader: false,
            requestBody: false,
            responseHeader: false,
            responseBody: false,
            logPrint: (o) => debugPrint(o.toString()),
          ),
      ]);

/// Whether a request may be repeated against a second configured origin.
///
/// Login is deliberately [never]: once credentials have left this process,
/// a timeout cannot establish whether the server created a session. Replaying
/// the same login elsewhere could create two sessions or select the wrong one.
enum FallbackPolicy { networkErrors, never }

typedef SessionCredentialReader = SessionCredential? Function();

/// Reads the auth generation a request is being issued under.
typedef AuthGenerationReader = int Function();

/// Hands a failed request back to whoever owns auth state, tagged with the
/// generation it was issued under. The owner decides whether it ends a session.
typedef SessionEndReporter =
    void Function(Object error, {required int generation});

class ApiClientException implements Exception {
  const ApiClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The configured backend cannot legitimately hold this app's credential.
///
/// Raised before any request goes out, because the alternative is discovering
/// it by having sent the token somewhere it does not belong.
class UnsupportedOriginException implements Exception {
  const UnsupportedOriginException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// No backend URL is configured for the current mode (custom-only with an
/// empty custom URL). A configuration problem, not an outage: retrying cannot
/// heal it, only a settings change can, and callers classify it accordingly.
class MissingBackendUrlException implements Exception {
  const MissingBackendUrlException(this.message);

  final String message;

  @override
  String toString() => message;
}

SessionCredentialReader? _credentialReader;
AuthGenerationReader? _generationReader;
SessionEndReporter? _sessionEndReporter;

/// Wire the client to whatever owns auth.
///
/// Reporting failures from here rather than from each service is what makes the
/// designated-request rule hold everywhere at once: every app-issued request
/// goes through this function, carries the generation it was issued under, and
/// hands its failure back with that generation attached. A service that forgot
/// to report would otherwise be a silent hole in the state machine.
void configureApiAuth({
  required SessionCredentialReader credentialReader,
  AuthGenerationReader? generationReader,
  SessionEndReporter? sessionEndReporter,
}) {
  _credentialReader = credentialReader;
  _generationReader = generationReader;
  _sessionEndReporter = sessionEndReporter;
}

@visibleForTesting
void resetApiAuth() {
  _credentialReader = null;
  _generationReader = null;
  _sessionEndReporter = null;
}

/// The one seam tests use to answer requests without a server. Kept narrow on
/// purpose: everything else about the client — origin rules, credential
/// attachment, CSRF — stays under test rather than being stubbed around.
@visibleForTesting
HttpClientAdapter get apiHttpClientAdapter => _dio.httpClientAdapter;

@visibleForTesting
set apiHttpClientAdapter(HttpClientAdapter adapter) =>
    _dio.httpClientAdapter = adapter;

/// Sends a POST request to [path], respecting [BackendUrlMode] from [settings].
///
/// In [BackendUrlMode.builtin] mode the built-in compile-time URL is used.
/// In [BackendUrlMode.customWithFallback] mode the custom URL is tried first;
/// on any network error the request is retried against the built-in URL.
/// In [BackendUrlMode.customOnly] mode only the custom URL is tried.
Future<Response<dynamic>> apiPost(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  required dynamic body,
  FallbackPolicy fallbackPolicy = FallbackPolicy.networkErrors,
}) => _requestWithFallback(
  'POST',
  path,
  settings: settings,
  headers: headers,
  body: body,
  fallbackPolicy: fallbackPolicy,
);

/// Revoke a bearer session that was issued but could not be stored durably.
///
/// The credential is explicit because installing it as the app's current
/// session, even briefly, would let unrelated requests observe a login that
/// has already failed. This request is never replayed against another origin.
Future<Response<dynamic>> revokeIssuedBearerSession(
  SessionCredential credential, {
  required AppSettingsController? settings,
}) => _requestWithFallback(
  'POST',
  '/auth/logout/',
  settings: settings,
  headers: jsonHeaders,
  body: const <String, dynamic>{},
  fallbackPolicy: FallbackPolicy.never,
  credentialOverride: credential,
);

Future<Response<dynamic>> apiGet(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) => _requestWithFallback('GET', path, settings: settings, headers: headers);

Future<Response<List<int>>> apiGetBytes(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) async {
  final response = await _requestWithFallback(
    'GET',
    path,
    settings: settings,
    headers: headers,
    responseType: ResponseType.bytes,
  );
  return Response<List<int>>(
    data: response.data is List<int> ? response.data as List<int> : null,
    headers: response.headers,
    requestOptions: response.requestOptions,
    statusCode: response.statusCode,
    statusMessage: response.statusMessage,
    redirects: response.redirects,
    extra: response.extra,
    isRedirect: response.isRedirect,
  );
}

Future<Response<dynamic>> apiPatch(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  required dynamic body,
}) => _requestWithFallback(
  'PATCH',
  path,
  settings: settings,
  headers: headers,
  body: body,
);

Future<Response<dynamic>> apiDelete(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) =>
    _requestWithFallback('DELETE', path, settings: settings, headers: headers);

List<String> resolveUrls(String path, AppSettingsController? settings) {
  final mode = settings?.backendUrlMode ?? BackendUrlMode.builtin;
  final custom = settings?.customBackendUrl.trim() ?? '';

  switch (mode) {
    case BackendUrlMode.builtin:
      return [_effectiveBuiltinApiUrl];
    case BackendUrlMode.customWithFallback:
      if (custom.isEmpty) return [_effectiveBuiltinApiUrl];
      return [custom, _effectiveBuiltinApiUrl];
    case BackendUrlMode.customOnly:
      if (custom.isEmpty) return [];
      return [custom];
  }
}

/// Whether the app is allowed to send credentials to [baseUrl].
///
/// Two different rules, because the two platforms hold two different things:
///
/// * **Web** is same-origin-only, not merely same-site. The `csrftoken` cookie
///   is host-scoped, so JS on `app.example.com` cannot read one set by
///   `api.example.com` — a same-site-but-cross-origin backend could
///   authenticate but never pass CSRF. Rejecting it here turns a confusing
///   run-time 403 into a settings-time error.
/// * **Native** pins the token to the origin that issued it, and requires that
///   origin to be HTTPS: a credential that outlives a single request must never
///   travel in plaintext.
///
/// Loopback is the documented exception on both. Flutter's dev server and
/// Django run on different ports of the same host, so dev compares host only
/// (and Django's port-exact CSRF check is satisfied by pinning the Flutter web
/// port in `CSRF_TRUSTED_ORIGINS` — see backend `DEV_WEB_PORT`).
String? describeUnsupportedOrigin(
  String baseUrl, {
  SessionCredential? credential,
}) {
  final target = Uri.tryParse(baseUrl);
  if (target == null || !target.hasScheme || target.host.isEmpty) {
    return 'Backend URL "$baseUrl" is not a usable http(s) URL.';
  }

  if (kIsWeb) {
    final page = Uri.base;
    if (_sameOrigin(page, target)) {
      return null;
    }
    return 'Web builds are same-origin-only: this page is served from '
        '${page.origin} but the backend is configured as ${target.origin}. '
        'The CSRF cookie is host-scoped, so a cross-origin backend cannot be '
        'used from the browser.';
  }

  if (!_isSecureOrigin(target)) {
    return 'Refusing to send a session token to ${target.origin}: bearer '
        'sessions require HTTPS (loopback excepted for development).';
  }

  if (credential != null &&
      !_sameOrigin(Uri.parse(credential.origin), target)) {
    return 'This session belongs to ${credential.origin} and will not be sent '
        'to ${target.origin}. Sign in again after changing the backend URL.';
  }

  return null;
}

bool _isLoopback(Uri uri) =>
    uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

bool _isSecureOrigin(Uri uri) => uri.scheme == 'https' || _isLoopback(uri);

bool _sameOrigin(Uri left, Uri right) {
  if (left.scheme != right.scheme || left.host != right.host) {
    return false;
  }
  // The dev web server and Django use different ports on the same loopback
  // host. Scheme and host remain exact so localhost, 127.0.0.1 and HTTPS are
  // not silently treated as interchangeable credential boundaries.
  if (_isLoopback(left)) {
    return true;
  }
  return left.port == right.port;
}

Uri _buildRequestUri(String baseUrl, String path) {
  final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
  return Uri.parse('$normalizedBaseUrl/$normalizedPath');
}

Future<Response<dynamic>> _requestWithFallback(
  String method,
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  dynamic body,
  ResponseType? responseType,
  FallbackPolicy fallbackPolicy = FallbackPolicy.networkErrors,
  SessionCredential? credentialOverride,
}) async {
  final urls = resolveUrls(path, settings);
  if (urls.isEmpty) {
    throw MissingBackendUrlException(
      '$method $path failed: no backend URL configured',
    );
  }

  Object? lastError;

  for (final url in urls) {
    try {
      return await _performRequest(
        method,
        url,
        path,
        headers: headers,
        body: body,
        responseType: responseType,
        credentialOverride: credentialOverride,
      );
    } on DioException catch (error) {
      lastError = error;
      final shouldTryFallback =
          fallbackPolicy == FallbackPolicy.networkErrors &&
          !identical(url, urls.last) &&
          _isFallbackableNetworkError(error);
      if (!shouldTryFallback) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '$method ${_buildRequestUri(url, path)} failed (${error.type}), '
          'trying fallback',
        );
      }
    } on UnsupportedOriginException catch (error) {
      // Not a transport failure — the fallback URL may still be usable, but
      // this one is disqualified on principle, so never retry it.
      lastError = error;
      if (fallbackPolicy == FallbackPolicy.never || identical(url, urls.last)) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint('$method $url refused ($error), trying fallback');
      }
    } on FormatException catch (error) {
      lastError = error;
      if (fallbackPolicy == FallbackPolicy.never || identical(url, urls.last)) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint('$method $url invalid ($error), trying fallback');
      }
    }
  }

  throw ApiClientException(
    '$method $path failed: ${lastError ?? 'all URLs exhausted'}',
  );
}

Future<Response<dynamic>> _performRequest(
  String method,
  String baseUrl,
  String path, {
  required Map<String, String> headers,
  dynamic body,
  ResponseType? responseType,
  SessionCredential? credentialOverride,
}) async {
  final credential = credentialOverride ?? _credentialReader?.call();
  final refusal = describeUnsupportedOrigin(baseUrl, credential: credential);
  if (refusal != null) {
    throw UnsupportedOriginException(refusal);
  }

  // Captured before dispatch, not after: what matters is the state the request
  // was issued under, so a response arriving after a login/logout is ignored.
  final generation = _generationReader?.call() ?? 0;

  try {
    return await _dio.requestUri<dynamic>(
      _buildRequestUri(baseUrl, path),
      data: body,
      options: Options(
        method: method,
        headers: _headersWithCredentials(method, headers, credential),
        responseType: responseType,
        // The browser adapter reads this per request; on other platforms it is
        // inert. Set unconditionally so the cookie rides along on web without a
        // conditional import just to configure the adapter.
        extra: const {'withCredentials': true},
      ),
    );
  } on DioException catch (error) {
    _sessionEndReporter?.call(error, generation: generation);
    rethrow;
  }
}

Map<String, String> _headersWithCredentials(
  String method,
  Map<String, String> headers,
  SessionCredential? credential,
) {
  final result = <String, String>{...headers};

  if (credential != null) {
    result['Authorization'] = '$sessionAuthScheme ${credential.token}';
  }

  if (kIsWeb && !_csrfSafeMethods.contains(method.toUpperCase())) {
    final csrfToken = readBrowserCookie(csrfCookieName);
    if (csrfToken != null) {
      result[csrfHeaderName] = csrfToken;
    }
    // A missing token is not worth failing on locally: the server rejects the
    // write with a 403 that names CSRF, which is a far more useful signal than
    // a client-side guess about why the cookie is absent.
  }

  return result;
}

bool _isFallbackableNetworkError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.badCertificate:
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return true;
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;
  }
}

/// Whether a 401 is *this API* saying the session is over.
///
/// The header is the whole point: an edge, proxy or captive portal can return
/// 401 for reasons that have nothing to do with the session, and signing the
/// user out on those would make every flaky network a logout.
bool isSessionChallenge(Response<dynamic>? response) {
  if (response == null || response.statusCode != 401) {
    return false;
  }
  final challenge = response.headers.value('www-authenticate');
  return challenge != null &&
      challenge.trim().toLowerCase().startsWith(
        sessionAuthScheme.toLowerCase(),
      );
}

/// Validates [response] is 200 and returns decoded JSON as `Map<String, dynamic>`.
/// Throws a descriptive [Exception] on any non-200 status.
Map<String, dynamic> expectSuccessJson(
  Response<dynamic> response,
  String context,
) {
  expectSuccessStatus(response, context, successCodes: const {200});
  if (response.data is Map) {
    return Map<String, dynamic>.from(response.data as Map);
  }

  throw Exception(
    "$context failed: expected a JSON object but got "
    "${_describeResponseShape(response.data)}.",
  );
}

List<dynamic> expectSuccessList(Response<dynamic> response, String context) {
  expectSuccessStatus(response, context, successCodes: const {200});
  if (response.data is List) {
    return List<dynamic>.from(response.data as List);
  }

  throw Exception(
    "$context failed: expected a JSON array but got "
    "${_describeResponseShape(response.data)}.",
  );
}

void expectSuccessStatus(
  Response<dynamic> response,
  String context, {
  Set<int>? successCodes,
}) {
  final statusCode = response.statusCode;
  final isSuccess = successCodes != null
      ? successCodes.contains(statusCode)
      : statusCode != null && statusCode >= 200 && statusCode < 300;
  if (isSuccess) {
    return;
  }

  throw Exception(
    "$context failed: (${response.statusCode}) "
    "${response.data}",
  );
}

String _describeResponseShape(dynamic value) {
  if (value == null) {
    return "no body";
  }
  if (value is Map) {
    return "a JSON object";
  }
  if (value is List) {
    return "a JSON array";
  }
  return value.runtimeType.toString();
}
