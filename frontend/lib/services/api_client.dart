import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/services/app_settings.dart';

const String builtinApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

const Duration connectTimeout = Duration(seconds: 10);
const Duration receiveTimeout = Duration(seconds: 15);

/// Shared Dio instance — connection pooling happens here.
final Dio _dio = Dio(BaseOptions(
  connectTimeout: connectTimeout,
  receiveTimeout: receiveTimeout,
))..interceptors.addAll([
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
  ]);

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
  for (final baseUrl in urls) {
    try {
      final fullUrl = '$baseUrl$path';
      final response = await _dio.post(fullUrl, data: body,
        options: Options(headers: headers),
      );
      return response;
    } catch (e) {
      if (identical(baseUrl, urls.last)) rethrow;
      if (kDebugMode) debugPrint('apiPost: $baseUrl failed ($e), trying fallback');
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
  for (final baseUrl in urls) {
    try {
      final fullUrl = '$baseUrl$path';
      final response = await _dio.get(fullUrl,
        options: Options(headers: headers),
      );
      return response;
    } catch (e) {
      if (identical(baseUrl, urls.last)) rethrow;
      if (kDebugMode) debugPrint('apiGet: $baseUrl failed ($e), trying fallback');
    }
  }
  throw StateError('apiGet: all URLs exhausted');
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

/// Validates [response] is 200 and returns decoded JSON as `Map<String, dynamic>`.
/// Throws a descriptive [Exception] on any non-200 status.
Map<String, dynamic> expectSuccessJson(Response response, String context) {
  if (response.statusCode == 200) {
    return response.data as Map<String, dynamic>;
  }
  throw Exception(
    '$context failed: (${response.statusCode}) ${response.data}',
  );
}
