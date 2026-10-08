import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:notif/services/session_store.dart';

/// A keystore that lives in a variable. Lets tests assert on what the app
/// persisted and, crucially, on what it deleted.
class InMemorySessionStore implements SessionStore {
  InMemorySessionStore({SessionCredential? initial}) : _record = initial;

  SessionCredential? _record;

  /// Set to make the next operation of that name blow up, so the "keystore
  /// trouble is reported, not swallowed" paths are exercisable.
  String? failOn;

  int writes = 0;
  int deletes = 0;

  SessionCredential? get record => _record;

  @override
  Future<SessionCredential?> read() async {
    if (failOn == 'read') {
      throw const SessionStoreException('read', 'keystore unavailable');
    }
    return _record;
  }

  @override
  Future<void> write(SessionCredential credential) async {
    writes++;
    if (failOn == 'write') {
      throw const SessionStoreException('write', 'keystore unavailable');
    }
    _record = credential;
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (failOn == 'delete') {
      throw const SessionStoreException('delete', 'keystore unavailable');
    }
    _record = null;
  }
}

/// One canned reply.
class FakeReply {
  const FakeReply({
    required this.statusCode,
    this.body,
    this.headers = const {},
    this.throwsConnectionError = false,
  });

  /// The server is unreachable — a transport failure, not a verdict.
  const FakeReply.offline()
    : statusCode = 0,
      body = null,
      headers = const {},
      throwsConnectionError = true;

  /// Our own 401: the challenge header is what makes it end a session.
  const FakeReply.sessionChallenge()
    : statusCode = 401,
      body = const {'detail': 'Invalid or expired session token.'},
      headers = const {
        'www-authenticate': ['Session'],
      },
      throwsConnectionError = false;

  /// A 401 from something in front of the API — an edge, a proxy, a portal.
  const FakeReply.edgeUnauthorized()
    : statusCode = 401,
      body = null,
      headers = const {},
      throwsConnectionError = false;

  final int statusCode;
  final Object? body;
  final Map<String, List<String>> headers;
  final bool throwsConnectionError;
}

class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final Object? body;

  String get path => uri.path;

  String? get authorization => headers['Authorization'] as String?;
}

/// Answers requests by path suffix, in order, recording what it saw.
class FakeApiAdapter implements HttpClientAdapter {
  FakeApiAdapter();

  final Map<String, List<FakeReply>> _queues = {};
  final List<RecordedRequest> requests = [];

  void enqueue(String pathSuffix, FakeReply reply) {
    _queues.putIfAbsent(pathSuffix, () => []).add(reply);
  }

  RecordedRequest requestFor(String pathSuffix) =>
      requests.firstWhere((request) => request.path.endsWith(pathSuffix));

  bool sawRequestFor(String pathSuffix) =>
      requests.any((request) => request.path.endsWith(pathSuffix));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      RecordedRequest(
        options.method,
        options.uri,
        Map<String, dynamic>.from(options.headers),
        options.data,
      ),
    );

    final key = _queues.keys.firstWhere(
      (suffix) => options.uri.path.endsWith(suffix),
      orElse: () => throw StateError('No canned reply for ${options.uri.path}'),
    );
    final queue = _queues[key]!;
    final reply = queue.length == 1 ? queue.first : queue.removeAt(0);

    if (reply.throwsConnectionError) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'fake offline',
      );
    }

    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const Map<String, dynamic> fakeUserJson = {
  'id': 7,
  'name': 'Test',
  'email': 'test@example.com',
  'username': 'tester',
  'is_staff': false,
  'is_superuser': false,
  'date_created': '2026-01-01T00:00:00Z',
  'date_modified': '2026-01-01T00:00:00Z',
  'date_deleted': null,
};
