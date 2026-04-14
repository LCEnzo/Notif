import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/services/app_settings.dart';

const String builtinApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

const Duration connectTimeout = Duration(seconds: 10);
const Duration receiveTimeout = Duration(seconds: 15);

/// Sends a POST request to [path], respecting [BackendUrlMode] from [settings].
///
/// In [BackendUrlMode.builtin] mode the built-in compile-time URL is used.
/// In [BackendUrlMode.customWithFallback] mode the custom URL is tried first;
/// on any network error the request is retried against the built-in URL.
/// In [BackendUrlMode.customOnly] mode only the custom URL is tried.
Future<Response> apiPost(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
  required dynamic body,
}) async {
  final urls = resolveUrls(path, settings);
  for (final url in urls) {
    try {
      final dio = _createDio(url, headers);
      final response = await dio.post(path, data: body);
      return response;
    } catch (e) {
      if (identical(url, urls.last)) rethrow;
      if (kDebugMode) debugPrint('apiPost: $url failed ($e), trying fallback');
    }
  }
  throw StateError('apiPost: all URLs exhausted');
}

Future<Response> apiGet(
  String path, {
  required AppSettingsController? settings,
  required Map<String, String> headers,
}) async {
  final urls = resolveUrls(path, settings);
  for (final url in urls) {
    try {
      final dio = _createDio(url, headers);
      final response = await dio.get(path);
      return response;
    } catch (e) {
      if (identical(url, urls.last)) rethrow;
      if (kDebugMode) debugPrint('apiGet: $url failed ($e), trying fallback');
    }
  }
  throw StateError('apiGet: all URLs exhausted');
}

Dio _createDio(String baseUrl, Map<String, String> headers) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: headers,
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
    );
  }

  return dio;
}

List<String> resolveUrls(String path, AppSettingsController? settings) {
  final mode = settings?.backendUrlMode ?? BackendUrlMode.builtin;
  final custom = settings?.customBackendUrl ?? '';

  switch (mode) {
    case BackendUrlMode.builtin:
      return [builtinApiUrl];
    case BackendUrlMode.customWithFallback:
      if (custom.isEmpty) return [builtinApiUrl];
      return [custom, builtinApiUrl];
    case BackendUrlMode.customOnly:
      if (custom.isEmpty) return [];
      return [custom];
  }
}
