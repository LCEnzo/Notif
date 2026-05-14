import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:notif/services/persistence.dart';

const _nativeRefreshCookieStoreKey = 'nativeRefreshCookies';
const _refreshCookieName = 'notif_refresh';
const _refreshCookiePathPrefix = '/token/';
const _refreshCookieFallbackLifetime = Duration(hours: 72);

final class _NativeRefreshCookie {
  const _NativeRefreshCookie({
    required this.value,
    required this.expiresAt,
  });

  final String value;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
}

Future<String?> nativeRefreshCookieHeader(
  Uri requestUri,
  String apiPath,
) async {
  if (kIsWeb || !_isRefreshCookiePath(apiPath)) {
    return null;
  }

  final now = DateTime.now().toUtc();
  final cookies = await _loadNativeRefreshCookies();
  final key = _originKey(requestUri);
  final cookie = cookies[key];
  if (cookie == null) {
    return null;
  }
  if (cookie.isExpired(now)) {
    cookies.remove(key);
    await _saveNativeRefreshCookies(cookies);
    return null;
  }
  return '$_refreshCookieName=${cookie.value}';
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
    changed = true;
    if (parsed.shouldDelete) {
      cookies.remove(origin);
    } else {
      cookies[origin] = _NativeRefreshCookie(
        value: parsed.value,
        expiresAt: parsed.expiresAt,
      );
    }
  }

  if (changed) {
    await _saveNativeRefreshCookies(cookies);
  }
}

Future<void> clearNativeRefreshCookies() async {
  if (kIsWeb) return;
  final store = await PreferenceStore.load();
  await store.remove(_nativeRefreshCookieStoreKey);
}

bool _isRefreshCookiePath(String apiPath) {
  final normalized = apiPath.startsWith('/') ? apiPath : '/$apiPath';
  return normalized.startsWith(_refreshCookiePathPrefix);
}

String _originKey(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';

Future<Map<String, _NativeRefreshCookie>> _loadNativeRefreshCookies() async {
  final store = await PreferenceStore.load();
  try {
    final raw = store.read<String>(_nativeRefreshCookieStoreKey);
    if (raw == null || raw.trim().isEmpty) {
      return {};
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      await store.remove(_nativeRefreshCookieStoreKey);
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
      );
    }
    return cookies;
  } on FormatException {
    await store.remove(_nativeRefreshCookieStoreKey);
    return {};
  } on PreferenceException {
    await store.remove(_nativeRefreshCookieStoreKey);
    return {};
  }
}

Future<void> _saveNativeRefreshCookies(
  Map<String, _NativeRefreshCookie> cookies,
) async {
  final store = await PreferenceStore.load();
  if (cookies.isEmpty) {
    await store.remove(_nativeRefreshCookieStoreKey);
    return;
  }

  await store.writeString(
    _nativeRefreshCookieStoreKey,
    jsonEncode({
      for (final entry in cookies.entries)
        entry.key: {
          'value': entry.value.value,
          'expiresAt': entry.value.expiresAt.millisecondsSinceEpoch,
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
  if (name != _refreshCookieName) {
    return null;
  }

  final value = parts.first.substring(firstSeparator + 1).trim();
  var shouldDelete = value.isEmpty;
  DateTime? expiresAt;
  final now = DateTime.now().toUtc();

  for (final part in parts.skip(1)) {
    final separator = part.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = part.substring(0, separator).trim().toLowerCase();
    final attributeValue = part.substring(separator + 1).trim();
    if (key != 'max-age') {
      continue;
    }
    final maxAgeSeconds = int.tryParse(attributeValue);
    if (maxAgeSeconds == null) {
      continue;
    }
    if (maxAgeSeconds <= 0) {
      shouldDelete = true;
    } else {
      expiresAt = now.add(Duration(seconds: maxAgeSeconds));
    }
  }

  return _ParsedRefreshCookie(
    value: value,
    expiresAt: expiresAt ?? now.add(_refreshCookieFallbackLifetime),
    shouldDelete: shouldDelete,
  );
}

final class _ParsedRefreshCookie {
  const _ParsedRefreshCookie({
    required this.value,
    required this.expiresAt,
    required this.shouldDelete,
  });

  final String value;
  final DateTime expiresAt;
  final bool shouldDelete;
}
