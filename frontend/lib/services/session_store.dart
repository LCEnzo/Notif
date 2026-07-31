import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The native credential: one opaque session token plus the origin it belongs to.
///
/// The pair is stored as a single record, so the token can never be read
/// without knowing where it is allowed to travel.
@immutable
class SessionCredential {
  const SessionCredential({required this.token, required this.origin});

  factory SessionCredential.fromJson(Map<String, dynamic> json) {
    final token = (json['token'] as String?)?.trim() ?? '';
    final origin = (json['origin'] as String?)?.trim() ?? '';
    if (token.isEmpty || origin.isEmpty) {
      throw const FormatException('Stored session record is missing a field');
    }
    return SessionCredential(token: token, origin: origin);
  }

  final String token;

  /// Scheme + host + port of the backend that issued this token. Requests only
  /// ever carry it here — a token minted by one deployment must never leak to
  /// another just because the user switched the backend URL setting.
  final String origin;

  Map<String, dynamic> toJson() => {'token': token, 'origin': origin};

  @override
  bool operator ==(Object other) =>
      other is SessionCredential &&
      other.token == token &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(token, origin);

  /// Never let the token reach a log, a crash report, or a client event.
  @override
  String toString() => 'SessionCredential(origin: $origin, token: <redacted>)';
}

/// A store operation failed. Callers report this rather than swallowing it:
/// a keystore delete that silently failed would claim a sign-out the next cold
/// start undoes.
class SessionStoreException implements Exception {
  const SessionStoreException(this.operation, this.cause);

  final String operation;
  final Object cause;

  @override
  String toString() => 'Secure storage $operation failed: $cause';
}

/// Where the platform keeps the credential.
///
/// Native holds a keystore record whose *existence is the restoration intent* —
/// there is no separate "remember me" flag that could drift out of sync with it.
/// Web holds nothing at all: the HttpOnly cookie is the credential, the browser
/// owns it, and any JS-side shadow of it could only desynchronize.
abstract class SessionStore {
  Future<SessionCredential?> read();

  Future<void> write(SessionCredential credential);

  Future<void> delete();
}

/// Native: one record in the platform keystore.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android backup exclusion is declarative, not an option here:
            // see android:allowBackup="false" in AndroidManifest.xml.
            iOptions: IOSOptions(
              // Device-only and unlocked-only: the credential must not ride an
              // iCloud Keychain sync to another device.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const String recordKey = 'notif.session.v1';

  /// Keys written by the JWT-era client. Deleted on first run of the new
  /// client; drop this list once the cutover has aged out.
  static const List<String> legacyKeys = [
    'notif.refresh_token',
    'notif.refresh.v1',
    'refresh_token',
  ];

  final FlutterSecureStorage _storage;

  @override
  Future<SessionCredential?> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: recordKey);
    } on Object catch (error) {
      // Platform channels throw arbitrary objects (PlatformException,
      // MissingPluginException, and whatever the keystore surfaces on a locked
      // device), so this is one of the few places a bare catch is right.
      throw SessionStoreException('read', error);
    }

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Stored session record is not an object');
      }
      return SessionCredential.fromJson(decoded);
    } on FormatException catch (error) {
      // A corrupt record is not a credential. Drop it rather than wedging every
      // future cold start on the same unparseable bytes.
      await _deleteQuietly();
      throw SessionStoreException('read', error);
    }
  }

  @override
  Future<void> write(SessionCredential credential) async {
    try {
      await _storage.write(
        key: recordKey,
        value: jsonEncode(credential.toJson()),
      );
    } on Object catch (error) {
      throw SessionStoreException('write', error);
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: recordKey);
    } on Object catch (error) {
      throw SessionStoreException('delete', error);
    }
  }

  /// Best-effort removal of pre-cutover credentials. Failures are ignored:
  /// nothing downstream depends on the old keys being gone.
  Future<void> deleteLegacyRecords() async {
    for (final key in legacyKeys) {
      try {
        await _storage.delete(key: key);
      } on Object catch (error) {
        if (kDebugMode) {
          debugPrint('SecureSessionStore.deleteLegacyRecords($key): $error');
        }
      }
    }
  }

  Future<void> _deleteQuietly() async {
    try {
      await _storage.delete(key: recordKey);
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('SecureSessionStore._deleteQuietly: $error');
      }
    }
  }
}

/// Web: the platform owns the credential, so this store holds nothing.
///
/// Not a stub — it is the honest model. Reading returns null because the
/// HttpOnly cookie is invisible to JS; the app learns its auth state by asking
/// the server, not by consulting a local record.
class PlatformOwnedSessionStore implements SessionStore {
  const PlatformOwnedSessionStore();

  @override
  Future<SessionCredential?> read() async => null;

  @override
  Future<void> write(SessionCredential credential) async {}

  @override
  Future<void> delete() async {}
}

SessionStore createSessionStore() =>
    kIsWeb ? const PlatformOwnedSessionStore() : SecureSessionStore();
