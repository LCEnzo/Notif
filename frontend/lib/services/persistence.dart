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
