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
    // not. The word boundary keeps identifiers like `_fromDio(` from matching.
    final constructsDio = RegExp(r'\bDio\(');
    for (final file in libFiles) {
      if (relative(file).endsWith('services/api_client.dart')) continue;
      expect(
        constructsDio.hasMatch(read(file)),
        isFalse,
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

  test('only the health services reach Health Connect', () {
    final offenders = libFiles
        .where((file) => read(file).contains('package:hc_bridge/'))
        .map(relative)
        .where((path) => !path.startsWith('lib/services/health/'))
        .toList();

    expect(
      offenders,
      isEmpty,
      reason:
          'Screens get Health Connect types through health_service.dart, so '
          'every HC call goes through the code that records grants and '
          'classifies failures.',
    );
  });

  test(
    'only the health scheduler owns WorkManager and a second auth wiring',
    () {
      final scheduler = libFiles
          .where((file) => read(file).contains('package:workmanager/'))
          .map(relative)
          .toList();
      expect(scheduler, ['lib/services/health/scheduler.dart']);

      final wiring = libFiles
          .where((file) => read(file).contains('configureApiAuth('))
          .map(relative)
          .toSet();
      expect(
        wiring,
        {
          'lib/services/api_client.dart',
          'lib/services/auth.dart',
          'lib/services/health/scheduler.dart',
        },
        reason:
            'The WorkManager isolate has no AuthService, so the scheduler wires '
            'the stored credential itself. Anything else doing so is a second '
            'auth stack.',
      );
    },
  );

  test('health state goes through PreferenceStore, not raw preferences', () {
    final offenders = libFiles
        .map(relative)
        .where((path) => path.startsWith('lib/services/health/'))
        .where(
          (path) => File(path).readAsStringSync().contains(
            'package:shared_preferences/',
          ),
        )
        .toList();

    expect(offenders, isEmpty);
  });
}
