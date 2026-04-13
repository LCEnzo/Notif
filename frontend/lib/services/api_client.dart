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
  http.Response? response;
  for (final url in urls) {
    try {
      response = await http.post(Uri.parse(url), headers: headers, body: body);
      return response;
    } catch (e) {
      if (identical(url, urls.last)) rethrow;
      if (kDebugMode) print('apiPost: $url failed ($e), trying fallback');
    }
  }
  return response!; // unreachable, but satisfies the analyzer
}

Future<http.Response> apiGet(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) async {
  final urls = resolveUrls(path, settings);
  http.Response? response;
  for (final url in urls) {
    try {
      response = await http.get(Uri.parse(url), headers: headers);
      return response;
    } catch (e) {
      if (identical(url, urls.last)) rethrow;
      if (kDebugMode) print('apiGet: $url failed ($e), trying fallback');
    }
  }
  return response!;
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
      if (custom.isEmpty) return ['$builtinApiUrl$path'];
      return ['$custom$path'];
  }
}
