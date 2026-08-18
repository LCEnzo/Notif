import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Boundaries that are cheap to violate by accident and expensive to notice.
/// Enforced here rather than in review folklore.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  String read(File file) => file.readAsStringSync();

  String relative(File file) => file.path.replaceAll(r'\', '/');

  test('only the session store touches secure storage', () {
    final offenders = libFiles
        .where((file) => read(file).contains('flutter_secure_storage'))
        .map(relative)
        .where((path) => !path.endsWith('services/session_store.dart'))
        .toList();

    expect(
      offenders,
      isEmpty,
      reason:
          'The keystore is reachable through SessionStore only. A second '
          'caller is a second place the credential can be written, read, or '
          'forgotten to delete.',
    );
  });

  test('only the api client touches dio', () {
    final offenders = libFiles
        .where((file) => read(file).contains("package:dio/dio.dart"))
        .map(relative)
        .where(
          (path) =>
              !path.endsWith('services/api_client.dart') &&
              // These three read DioException to classify a failure — auth.dart
              // into an auth state, data.dart into a message, failures.dart into
              // an AppFailure category. None constructs a Dio or issues a
              // request of its own, which is the thing this rule exists to
              // prevent.
              !path.endsWith('services/auth.dart') &&
              !path.endsWith('services/data.dart') &&
              !path.endsWith('services/failures.dart'),
        )
        .toList();

    // Guard the exemption: reading exception types is fine, owning a client is
    // not. failures.dart's fromDio factory classifies a DioException without
    // constructing a client, so it is exempt like auth.dart and data.dart.
    for (final file in libFiles) {
      if (relative(file).endsWith('services/api_client.dart')) continue;
      if (relative(file).endsWith('services/failures.dart')) continue;
      expect(
        read(file),
        isNot(contains('Dio(')),
        reason: '${relative(file)} must not construct its own Dio.',
      );
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Requests go through api_client so credential attachment, origin '
          'rules, CSRF and session-end reporting apply to all of them.',
    );
  });

  test('nothing outside the api client hand-builds an Authorization header', () {
    final offenders = libFiles
        .where((file) => read(file).contains("'Authorization'"))
        .map(relative)
        .where((path) => !path.endsWith('services/api_client.dart'))
        .toList();

    expect(
      offenders,
      isEmpty,
      reason:
          'A hand-built Authorization header bypasses the origin pinning that '
          'stops a token being sent to a backend that did not issue it.',
    );
  });

  test('only the api client reads browser cookies', () {
    final offenders = libFiles
        .where((file) => read(file).contains('readBrowserCookie('))
        .map(relative)
        .where(
          (path) =>
              !path.endsWith('services/api_client.dart') &&
              !path.startsWith('lib/commons/browser_cookies'),
        )
        .toList();

    expect(offenders, isEmpty);
  });
}
