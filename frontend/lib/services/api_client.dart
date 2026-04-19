import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:notif/services/app_settings.dart';

const String builtinApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

const Map<String, String> jsonHeaders = {
  'Content-Type': 'application/json; charset=UTF-8',
};

/// Posts to [path] respecting the [BackendUrlMode] from [settings].
///
/// In [BackendUrlMode.builtin] mode the built-in compile-time URL is used.
/// In [BackendUrlMode.customWithFallback] mode the custom URL is tried first;
/// on any network error the request is retried against the built-in URL.
/// In [BackendUrlMode.customOnly] mode only the custom URL is tried.
Future<http.Response> apiPost(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  required String body,
}) async {
  final urls = resolveUrls(path, settings);
  if (urls.isEmpty) {
    throw StateError(
      'No API URL resolved for POST $path. '
      'Set a custom backend URL or switch the network mode.',
    );
  }
  http.Response? response;
  Object? lastError;
  for (final url in urls) {
    try {
      if (kDebugMode) debugPrint('apiPost: POST $url');
      response = await http.post(Uri.parse(url), headers: headers, body: body);
      return response;
    } catch (e) {
      lastError = e;
      if (kDebugMode) debugPrint('apiPost: $url failed ($e), trying fallback');
    }
  }
  throw Exception('API POST failed for ${urls.join(' -> ')}: $lastError');
}

Future<http.Response> apiGet(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) async {
  final urls = resolveUrls(path, settings);
  if (urls.isEmpty) {
    throw StateError(
      'No API URL resolved for GET $path. '
      'Set a custom backend URL or switch the network mode.',
    );
  }
  http.Response? response;
  Object? lastError;
  for (final url in urls) {
    try {
      if (kDebugMode) debugPrint('apiGet: GET $url');
      response = await http.get(Uri.parse(url), headers: headers);
      return response;
    } catch (e) {
      lastError = e;
      if (kDebugMode) debugPrint('apiGet: $url failed ($e), trying fallback');
    }
  }
  throw Exception('API GET failed for ${urls.join(' -> ')}: $lastError');
}

List<String> resolveUrls(String path, AppSettingsController? settings) {
  final mode = settings?.backendUrlMode ?? BackendUrlMode.builtin;
  final custom = settings?.customBackendUrl ?? '';

  switch (mode) {
    case BackendUrlMode.builtin:
      return ['$builtinApiUrl$path'];
    case BackendUrlMode.customWithFallback:
      if (custom.isEmpty) return ['$builtinApiUrl$path'];
      return ['$custom$path', '$builtinApiUrl$path'];
    case BackendUrlMode.customOnly:
      if (custom.isEmpty) return [];
      return ['$custom$path'];
  }
}
