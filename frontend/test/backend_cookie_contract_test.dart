import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/refresh_cookie_store.dart';

/// The native refresh flow only works while the frontend's cookie name and path
/// agree with the backend's. Both sides hardcode them in unrelated files, so
/// without this test a rename on either side breaks remember-me on Android
/// silently — nothing fails until a real device tries to refresh.
void main() {
  final settingsFile = File('../backend/notif/settings.py');

  test('refresh cookie name and path match backend settings', () {
    if (!settingsFile.existsSync()) {
      markTestSkipped(
        'backend/notif/settings.py is not part of this checkout '
        '(${settingsFile.absolute.path})',
      );
      return;
    }

    final source = settingsFile.readAsStringSync();
    final backendName = _pythonStringSetting(source, 'JWT_REFRESH_COOKIE_NAME');
    final backendPath = _pythonStringSetting(source, 'JWT_REFRESH_COOKIE_PATH');

    expect(
      backendName,
      isNotNull,
      reason: 'JWT_REFRESH_COOKIE_NAME disappeared from backend settings',
    );
    expect(
      backendPath,
      isNotNull,
      reason: 'JWT_REFRESH_COOKIE_PATH disappeared from backend settings',
    );

    expect(
      refreshCookieName,
      backendName,
      reason:
          'refreshCookieName in refresh_cookie_store.dart must equal '
          'JWT_REFRESH_COOKIE_NAME in backend/notif/settings.py',
    );

    // The frontend stores API-relative paths; the backend's cookie path
    // includes the mount that builtinApiUrl carries.
    final apiMount = Uri.parse(
      builtinApiUrl,
    ).path.replaceFirst(RegExp(r'/+$'), '');
    expect(
      '$apiMount$refreshCookiePathPrefix',
      backendPath,
      reason:
          'refreshCookiePathPrefix plus the API mount must equal '
          'JWT_REFRESH_COOKIE_PATH in backend/notif/settings.py',
    );
  });
}

String? _pythonStringSetting(String source, String name) {
  final match = RegExp(
    '^$name\\s*=\\s*["\'](.*?)["\']',
    multiLine: true,
  ).firstMatch(source);
  return match?.group(1);
}
