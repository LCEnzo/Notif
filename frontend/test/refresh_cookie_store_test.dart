import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/persistence.dart';
import 'package:notif/services/refresh_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_store.dart';

void main() {
  late InMemorySecureStore secure;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = InMemorySecureStore();
    overrideSecureStore(secure);
    resetRefreshCookieStoreForTesting();
  });

  tearDown(() {
    overrideSecureStore(null);
    resetRefreshCookieStoreForTesting();
  });

  final origin = Uri.parse('https://api.example.com/api/v1/token/');
  final refreshUri = Uri.parse(
    'https://api.example.com/api/v1/token/refresh/',
  );

  Future<Map<String, Object?>> readPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {for (final key in prefs.getKeys()) key: prefs.get(key)};
  }

  test('stores native refresh cookies per backend origin', () async {
    await rememberNativeRefreshCookie(origin, [
      'notif_refresh=refresh-token; Max-Age=259200; Path=/api/v1/token/; HttpOnly; SameSite=Lax',
    ]);

    expect(
      await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
      'notif_refresh=refresh-token',
    );
    expect(
      await nativeRefreshCookieHeader(
        Uri.parse('https://other.example.com/api/v1/token/refresh/'),
        '/token/refresh/',
      ),
      isNull,
    );
    expect(
      await nativeRefreshCookieHeader(
        Uri.parse('https://api.example.com/api/v1/monitoring/links/'),
        '/monitoring/links/',
      ),
      isNull,
    );
  });

  test(
    'clears native refresh cookies from delete Set-Cookie headers',
    () async {
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Max-Age=259200; Path=/api/v1/token/',
      ]);
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=""; Max-Age=0; Path=/api/v1/token/',
      ]);

      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        isNull,
      );
    },
  );

  group('storage location', () {
    test('the refresh token never reaches SharedPreferences', () async {
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=plaintext-would-be-bad; Max-Age=259200; Path=/api/v1/token/',
      ]);

      final prefs = await readPreferences();
      expect(prefs.values.join('|'), isNot(contains('plaintext-would-be-bad')));
      expect(prefs.keys, isNot(contains('nativeRefreshCookies')));
      expect(
        secure.values.values.join('|'),
        contains('plaintext-would-be-bad'),
        reason: 'the cookie jar belongs in the platform keystore',
      );
    });

    test('clearing removes the keystore entry', () async {
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Max-Age=259200',
      ]);
      expect(secure.values, isNotEmpty);

      await clearNativeRefreshCookies();

      expect(secure.values, isEmpty);
      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        isNull,
      );
    });
  });

  group('legacy plaintext migration', () {
    test('moves the legacy jar into the keystore and deletes it', () async {
      final legacy = jsonEncode({
        'https://api.example.com:443': {
          'value': 'legacy-token',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 10))
              .millisecondsSinceEpoch,
        },
      });
      SharedPreferences.setMockInitialValues({'nativeRefreshCookies': legacy});

      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        'notif_refresh=legacy-token',
        reason: 'the migrated session must survive the move',
      );

      final prefs = await readPreferences();
      expect(
        prefs.keys,
        isNot(contains('nativeRefreshCookies')),
        reason: 'a plaintext copy left behind is a permanent leak',
      );
      expect(secure.values.values.join('|'), contains('legacy-token'));
    });

    test('legacy jar is dropped even when it cannot be re-stored', () async {
      SharedPreferences.setMockInitialValues({
        'nativeRefreshCookies': jsonEncode({
          'https://api.example.com:443': {
            'value': 'legacy-token',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 10))
                .millisecondsSinceEpoch,
          },
        }),
      });
      overrideSecureStore(_FailingSecureStore());

      await nativeRefreshCookieHeader(refreshUri, '/token/refresh/');

      final prefs = await readPreferences();
      expect(prefs.keys, isNot(contains('nativeRefreshCookies')));
    });
  });

  group('cookie attributes', () {
    test('a Secure cookie is not stored when it arrives over http', () async {
      final httpOrigin = Uri.parse('http://api.example.com/api/v1/token/');

      await rememberNativeRefreshCookie(httpOrigin, [
        'notif_refresh=refresh-token; Max-Age=259200; Secure',
      ]);

      expect(secure.values, isEmpty);
      expect(
        await nativeRefreshCookieHeader(
          Uri.parse('http://api.example.com/api/v1/token/refresh/'),
          '/token/refresh/',
        ),
        isNull,
      );
    });

    test('a Secure cookie is never sent over http', () async {
      // Stored over https, then requested over http for the same host: a
      // downgrade must not leak the credential.
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Max-Age=259200; Secure',
      ]);
      secure.values.updateAll(
        (key, value) => value.replaceAll(
          'https://api.example.com:443',
          'http://api.example.com:80',
        ),
      );

      expect(
        await nativeRefreshCookieHeader(
          Uri.parse('http://api.example.com/api/v1/token/refresh/'),
          '/token/refresh/',
        ),
        isNull,
      );
    });

    test('Expires is honoured when Max-Age is absent', () async {
      final expires = DateTime.now().toUtc().add(const Duration(hours: 48));
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Expires=${_httpDate(expires)}; Path=/api/v1/token/',
      ]);

      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        'notif_refresh=refresh-token',
      );
      final stored = jsonDecode(secure.values.values.single);
      if (stored is! Map<String, Object?>) {
        fail('cookie jar is not a JSON object: $stored');
      }
      final entry = stored.values.single;
      if (entry is! Map<String, Object?>) {
        fail('cookie entry is not a JSON object: $entry');
      }
      final expiresAtMs = entry['expiresAt'];
      if (expiresAtMs is! int) {
        fail('expiresAt is not an epoch millisecond value: $expiresAtMs');
      }
      final storedExpiry = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs,
        isUtc: true,
      );
      expect(
        storedExpiry.difference(expires).abs(),
        lessThan(const Duration(seconds: 2)),
      );
    });

    test('a past Expires deletes the cookie', () async {
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Max-Age=259200',
      ]);
      final past = DateTime.now().toUtc().subtract(const Duration(days: 1));
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Expires=${_httpDate(past)}',
      ]);

      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        isNull,
      );
    });

    test('no lifetime means a session cookie that is never persisted',
        () async {
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=session-token; Path=/api/v1/token/; HttpOnly',
      ]);

      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        'notif_refresh=session-token',
        reason: 'usable for this process',
      );
      expect(
        secure.values,
        isEmpty,
        reason: 'a session cookie must not outlive the process on disk',
      );

      resetRefreshCookieStoreForTesting();
      expect(
        await nativeRefreshCookieHeader(refreshUri, '/token/refresh/'),
        isNull,
      );
    });
  });
}

class _FailingSecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _httpDate(DateTime value) {
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_weekdays[utc.weekday - 1]}, ${two(utc.day)} '
      '${_months[utc.month - 1]} ${utc.year} '
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
}
