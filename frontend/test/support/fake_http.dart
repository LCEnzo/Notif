import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHttpHandler = FutureOr<ResponseBody> Function(
  RequestOptions options,
);

/// Records every request the app makes and answers it from [handler].
///
/// Installed on the app's own Dio instance (`apiDio`), so tests exercise the
/// real request pipeline — fallback ordering, retries, cookie handling — rather
/// than a stubbed-out copy of it.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FakeHttpHandler handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  /// Requests grouped by API path, for readable assertions.
  Iterable<RequestOptions> requestsFor(String pathSuffix) =>
      requests.where((request) => request.uri.path.endsWith(pathSuffix));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ...?headers,
    },
  );
}
