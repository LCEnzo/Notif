import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:notif/services/persistence.dart';

/// Name the backend sets the refresh cookie under.
///
/// Must stay equal to `JWT_REFRESH_COOKIE_NAME` in `backend/notif/settings.py`;
/// `test/backend_cookie_contract_test.dart` fails if the two drift, because a
/// rename on either side silently breaks native remember-me.
const String refreshCookieName = 'notif_refresh';

/// API-relative prefix of the backend's `JWT_REFRESH_COOKIE_PATH`. Paths here
/// exclude the `/api/v1` mount that [builtinApiUrl] carries.
const String refreshCookiePathPrefix = '/token/';

/// Key holding the encrypted cookie jar in the platform keystore.
const String _secureCookieStoreKey = 'notifRefreshCookies';

/// Pre-keystore key. Held the refresh token as plaintext JSON in
/// SharedPreferences (`shared_prefs/FlutterSharedPreferences.xml` on Android).
/// Read once, then deleted — see [_migrateLegacyPlaintextCookies].
const String _legacyPlaintextStoreKey = 'nativeRefreshCookies';

final class _NativeRefreshCookie {
  const _NativeRefreshCookie({
    required this.value,
    required this.expiresAt,
    required this.secure,
  });

  final String value;

  /// Null for a session cookie: no `Max-Age`, no `Expires`, so it must not
  /// outlive the process — and must never be written to disk.
  final DateTime? expiresAt;

  /// Cookie carried the `Secure` attribute, so it may only travel over https.
  final bool secure;

  bool get isSessionCookie => expiresAt == null;

  bool isExpired(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(now);
  }
}

/// Session cookies, kept for the process only.
final Map<String, _NativeRefreshCookie> _sessionCookies = {};

bool _legacyMigrationDone = false;

@visibleForTesting
void resetRefreshCookieStoreForTesting() {
  _sessionCookies.clear();
  _legacyMigrationDone = false;
}

Future<String?> nativeRefreshCookieHeader(
  Uri requestUri,
  String apiPath,
) async {
  if (kIsWeb || !_isRefreshCookiePath(apiPath)) {
    return null;
  }

  final now = DateTime.now().toUtc();
  final key = _originKey(requestUri);

  final sessionCookie = _sessionCookies[key];
  if (sessionCookie != null) {
    return _headerFor(sessionCookie, requestUri);
  }

  final cookies = await _loadNativeRefreshCookies();
  final cookie = cookies[key];
  if (cookie == null) {
    return null;
  }
  if (cookie.isExpired(now)) {
    cookies.remove(key);
    await _saveNativeRefreshCookies(cookies);
    return null;
  }
  return _headerFor(cookie, requestUri);
}

String? _headerFor(_NativeRefreshCookie cookie, Uri requestUri) {
  if (cookie.secure && requestUri.scheme != 'https') {
    // Reachable: users can point the app at an http:// custom backend.
    if (kDebugMode) {
      debugPrint(
        'refresh_cookie_store: refusing to send the Secure refresh cookie '
        'over ${requestUri.scheme}:// to ${requestUri.host}',
      );
    }
    return null;
  }
  return '$refreshCookieName=${cookie.value}';
}

Future<void> rememberNativeRefreshCookie(
  Uri responseUri,
  Iterable<String> setCookieHeaders,
) async {
  if (kIsWeb || setCookieHeaders.isEmpty) {
    return;
  }

  final cookies = await _loadNativeRefreshCookies();
  var changed = false;
  final origin = _originKey(responseUri);
  for (final header in setCookieHeaders) {
    final parsed = _parseRefreshCookie(header);
    if (parsed == null) {
      continue;
    }
    if (parsed.secure && responseUri.scheme != 'https') {
      if (kDebugMode) {
        debugPrint(
          'refresh_cookie_store: refusing to store a Secure refresh cookie '
          'received over ${responseUri.scheme}:// from ${responseUri.host}',
        );
      }
      continue;
    }

    if (parsed.shouldDelete) {
      changed = cookies.remove(origin) != null || changed;
      _sessionCookies.remove(origin);
      continue;
    }

    final cookie = _NativeRefreshCookie(
      value: parsed.value,
      expiresAt: parsed.expiresAt,
      secure: parsed.secure,
    );
    if (cookie.isSessionCookie) {
      // No lifetime given: a session cookie. Inventing days of persistence for
      // it (the old behaviour) keeps a credential alive far past its intent.
      _sessionCookies[origin] = cookie;
      changed = cookies.remove(origin) != null || changed;
    } else {
      _sessionCookies.remove(origin);
      cookies[origin] = cookie;
      changed = true;
    }
  }

  if (changed) {
    await _saveNativeRefreshCookies(cookies);
  }
}

Future<void> clearNativeRefreshCookies() async {
  if (kIsWeb) return;
  _sessionCookies.clear();
  await secureStore.delete(_secureCookieStoreKey);
  try {
    final store = await PreferenceStore.load();
    await store.remove(_legacyPlaintextStoreKey);
  } on Exception catch (error) {
    if (kDebugMode) {
      debugPrint('clearNativeRefreshCookies: $error');
    }
  }
}

bool _isRefreshCookiePath(String apiPath) {
  final normalized = apiPath.startsWith('/') ? apiPath : '/$apiPath';
  return normalized.startsWith(refreshCookiePathPrefix);
}

String _originKey(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';

/// Moves any pre-keystore cookie jar into secure storage and deletes the
/// plaintext copy. Runs once per process, before the first read.
///
/// The delete happens even when the secure write fails: leaving a plaintext
/// refresh token on disk forever is worse than one forced re-login.
Future<void> _migrateLegacyPlaintextCookies() async {
  if (_legacyMigrationDone) {
    return;
  }
  _legacyMigrationDone = true;

  String? legacy;
  try {
    final store = await PreferenceStore.load();
    legacy = store.read<String>(_legacyPlaintextStoreKey);
    if (legacy == null) {
      return;
    }
    await store.remove(_legacyPlaintextStoreKey);
  } on Exception catch (error) {
    if (kDebugMode) {
      debugPrint('refresh_cookie_store legacy migration failed: $error');
    }
    return;
  }

  if (legacy.trim().isEmpty) {
    return;
  }
  final existing = await secureStore.read(_secureCookieStoreKey);
  if (existing == null || existing.trim().isEmpty) {
    await secureStore.write(_secureCookieStoreKey, legacy);
  }
}

Future<Map<String, _NativeRefreshCookie>> _loadNativeRefreshCookies() async {
  await _migrateLegacyPlaintextCookies();

  final raw = await secureStore.read(_secureCookieStoreKey);
  if (raw == null || raw.trim().isEmpty) {
    return {};
  }

  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      await secureStore.delete(_secureCookieStoreKey);
      return {};
    }

    final cookies = <String, _NativeRefreshCookie>{};
    for (final entry in decoded.entries) {
      final origin = entry.key;
      final value = entry.value;
      if (origin is! String || value is! Map<Object?, Object?>) {
        continue;
      }
      final cookieValue = value['value'];
      final expiresAtMs = value['expiresAt'];
      if (cookieValue is! String ||
          cookieValue.isEmpty ||
          expiresAtMs is! int) {
        continue;
      }
      cookies[origin] = _NativeRefreshCookie(
        value: cookieValue,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          expiresAtMs,
          isUtc: true,
        ),
        secure: value['secure'] == true,
      );
    }
    return cookies;
  } on FormatException {
    await secureStore.delete(_secureCookieStoreKey);
    return {};
  }
}

Future<void> _saveNativeRefreshCookies(
  Map<String, _NativeRefreshCookie> cookies,
) async {
  if (cookies.isEmpty) {
    await secureStore.delete(_secureCookieStoreKey);
    return;
  }

  await secureStore.write(
    _secureCookieStoreKey,
    jsonEncode({
      for (final entry in cookies.entries)
        entry.key: {
          'value': entry.value.value,
          'expiresAt': entry.value.expiresAt?.millisecondsSinceEpoch,
          'secure': entry.value.secure,
        },
    }),
  );
}

_ParsedRefreshCookie? _parseRefreshCookie(String header) {
  final parts = header.split(';');
  if (parts.isEmpty) {
    return null;
  }

  final firstSeparator = parts.first.indexOf('=');
  if (firstSeparator <= 0) {
    return null;
  }

  final name = parts.first.substring(0, firstSeparator).trim();
  if (name != refreshCookieName) {
    return null;
  }

  final value = parts.first.substring(firstSeparator + 1).trim();
  var shouldDelete = value.isEmpty || value == '""';
  var secure = false;
  DateTime? fromMaxAge;
  DateTime? fromExpires;
  String? path;
  final now = DateTime.now().toUtc();

  for (final part in parts.skip(1)) {
    final separator = part.indexOf('=');
    if (separator <= 0) {
      if (part.trim().toLowerCase() == 'secure') {
        secure = true;
      }
      continue;
    }

    final key = part.substring(0, separator).trim().toLowerCase();
    final attributeValue = part.substring(separator + 1).trim();
    switch (key) {
      case 'max-age':
        final maxAgeSeconds = int.tryParse(attributeValue);
        if (maxAgeSeconds == null) {
          continue;
        }
        if (maxAgeSeconds <= 0) {
          shouldDelete = true;
        } else {
          fromMaxAge = now.add(Duration(seconds: maxAgeSeconds));
        }
      case 'expires':
        final expires = _parseHttpDate(attributeValue);
        if (expires == null) {
          continue;
        }
        if (!expires.isAfter(now)) {
          shouldDelete = true;
        } else {
          fromExpires = expires;
        }
      case 'path':
        path = attributeValue;
      default:
        continue;
    }
  }

  if (path != null && !path.endsWith(refreshCookiePathPrefix)) {
    if (kDebugMode) {
      debugPrint(
        'refresh_cookie_store: cookie Path "$path" does not end with '
        '"$refreshCookiePathPrefix" — native refresh may not send it',
      );
    }
  }

  return _ParsedRefreshCookie(
    value: value,
    // RFC 6265: Max-Age wins over Expires. Neither present means a session
    // cookie, represented as a null expiry.
    expiresAt: fromMaxAge ?? fromExpires,
    secure: secure,
    shouldDelete: shouldDelete,
  );
}

const List<String> _httpDateMonths = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

final RegExp _httpDatePattern = RegExp(
  r'^[A-Za-z]+,\s*(\d{1,2})[ \-]([A-Za-z]{3})[ \-](\d{2,4})\s+'
  r'(\d{1,2}):(\d{2}):(\d{2})(?:\s+(?:GMT|UTC))?$',
);

/// Parses the cookie date formats a server realistically emits (IMF-fixdate
/// and the RFC 850 variant Django/Werkzeug can produce). `dart:io`'s
/// `HttpDate.parse` is unavailable here because this file also compiles for web.
DateTime? _parseHttpDate(String value) {
  final match = _httpDatePattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }

  final month = _httpDateMonths.indexOf(match.group(2)!.toLowerCase()) + 1;
  if (month == 0) {
    return null;
  }

  var year = int.parse(match.group(3)!);
  if (year < 100) {
    year += year < 70 ? 2000 : 1900;
  }

  return DateTime.utc(
    year,
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

final class _ParsedRefreshCookie {
  const _ParsedRefreshCookie({
    required this.value,
    required this.expiresAt,
    required this.secure,
    required this.shouldDelete,
  });

  final String value;
  final DateTime? expiresAt;
  final bool secure;
  final bool shouldDelete;
}
