import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferenceException implements Exception {
  const PreferenceException(this.operation, this.cause);

  final String operation;
  final Object cause;

  @override
  String toString() => 'PreferenceException($operation): $cause';
}

class CorruptLocalStateException extends PreferenceException {
  CorruptLocalStateException({
    required this.key,
    required this.expected,
    required this.actual,
  }) : super('read $key', 'expected $expected but found $actual');

  final String key;
  final String expected;
  final String actual;
}

class PreferenceStore {
  const PreferenceStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<PreferenceStore> load() async {
    return PreferenceStore._(await SharedPreferences.getInstance());
  }

  T? read<T extends Object>(String key) {
    final value = _prefs.get(key);
    if (value == null) {
      return null;
    }
    if (value is T) {
      return value;
    }
    throw CorruptLocalStateException(
      key: key,
      expected: '$T',
      actual: value.runtimeType.toString(),
    );
  }

  Future<void> writeBool(String key, bool value) async {
    await _write('writeBool $key', _prefs.setBool(key, value));
  }

  Future<void> writeString(String key, String value) async {
    await _write('writeString $key', _prefs.setString(key, value));
  }

  Future<void> remove(String key) async {
    await _write('remove $key', _prefs.remove(key));
  }

  Future<void> _write(String operation, Future<bool> write) async {
    final ok = await write;
    if (!ok) {
      throw PreferenceException(
        operation,
        'SharedPreferences refused the write',
      );
    }
  }
}

/// Storage for secrets — anything that grants access on its own, so never
/// [PreferenceStore], which is a world-readable XML file on Android.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Platform keystore-backed implementation.
///
/// Android: `flutter_secure_storage` 10 encrypts values with AES-GCM under an
/// RSA-OAEP key held in the Android KeyStore by default (the old
/// `encryptedSharedPreferences` flag is deprecated there and ignored).
/// Apple platforms use the Keychain, Windows the credential store, Linux
/// libsecret.
///
/// Failures degrade to "no value" rather than propagating: a missing plugin or
/// locked keyring must cost the user a re-login, never a crash, and must never
/// fall back to plaintext storage.
class PlatformSecureStore implements SecureKeyValueStore {
  const PlatformSecureStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions.defaultOptions,
    // *_this_device: a refresh token must not ride along to another device
    // through Keychain sync or a device-to-device transfer.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (error) {
      _reportFailure('read', key, error);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object catch (error) {
      _reportFailure('write', key, error);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object catch (error) {
      _reportFailure('delete', key, error);
    }
  }

  void _reportFailure(String operation, String key, Object error) {
    if (kDebugMode) {
      debugPrint('PlatformSecureStore.$operation($key) failed: $error');
    }
  }
}

SecureKeyValueStore? _secureStoreOverride;

/// The secure store the app uses. Tests replace it via [overrideSecureStore].
SecureKeyValueStore get secureStore =>
    _secureStoreOverride ?? const PlatformSecureStore();

@visibleForTesting
void overrideSecureStore(SecureKeyValueStore? store) {
  _secureStoreOverride = store;
}
