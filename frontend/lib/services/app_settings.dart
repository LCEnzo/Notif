import 'package:flutter/foundation.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthCardStyle { glass, framed }

enum HomeDensity { comfortable, compact, dense }

enum BackendUrlMode {
  /// Use only the built-in compile-time URL.
  builtin,

  /// Try the custom URL first; fall back to the built-in URL on failure.
  customWithFallback,

  /// Use only the custom URL — no fallback.
  customOnly,
}

/// Thrown when SharedPreferences read/write fails. The controller surfaces
/// failures via [AppSettingsController.persistenceError] so UI can show a
/// diagnostic rather than silently losing user changes.
class AppSettingsPersistenceException implements Exception {
  final String operation;
  final Object cause;
  final StackTrace stackTrace;

  AppSettingsPersistenceException(this.operation, this.cause, this.stackTrace);

  @override
  String toString() => 'AppSettingsPersistenceException($operation): $cause';
}

class AppSettingsController extends ChangeNotifier {
  static const String _ditheringKey = 'designDitheringEnabled';
  static const String _authCardStyleKey = 'debugAuthCardStyle';
  static const String _backendUrlModeKey = 'backendUrlMode';
  static const String _customBackendUrlKey = 'customBackendUrl';
  static const String _colorwayKey = 'colorway';
  static const String _fontSetKey = 'fontSet';
  static const String _homeDensityKey = 'homeDensity';

  bool _designDitheringEnabled = true;
  AuthCardStyle _authCardStyle = AuthCardStyle.framed;
  BackendUrlMode _backendUrlMode = BackendUrlMode.builtin;
  String _customBackendUrl = '';
  NotifColorway _colorway = NotifColorway.dusk1;
  NotifFontSet _fontSet = NotifFontSet.current;
  HomeDensity _homeDensity = HomeDensity.compact;

  /// Surface the most recent persistence failure so UI can show a banner.
  /// Cleared to `null` on the next successful operation.
  AppSettingsPersistenceException? _persistenceError;
  AppSettingsPersistenceException? get persistenceError => _persistenceError;

  bool _loaded = false;
  bool get loaded => _loaded;

  late final Future<void> initialized;

  AppSettingsController() {
    initialized = _load();
  }

  bool get designDitheringEnabled => _designDitheringEnabled;
  AuthCardStyle get authCardStyle => _authCardStyle;
  BackendUrlMode get backendUrlMode => _backendUrlMode;
  String get customBackendUrl => _customBackendUrl;
  NotifColorway get colorway => _colorway;
  NotifFontSet get fontSet => _fontSet;
  HomeDensity get homeDensity => _homeDensity;

  Future<void> _load() async {
    Object? loadError;
    StackTrace? loadStackTrace;

    T? readPref<T>(
      SharedPreferences prefs,
      String key,
      T? Function(String key) reader,
    ) {
      try {
        return reader(key);
      } catch (e, st) {
        loadError ??= StateError('Could not read "$key": $e');
        loadStackTrace ??= st;
        if (kDebugMode) debugPrint('AppSettings._load failed for $key: $e');
        return null;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final designDitheringEnabled =
          readPref<bool>(prefs, _ditheringKey, prefs.getBool) ?? true;
      final authCardStyle = _parseEnum(
        readPref<String>(prefs, _authCardStyleKey, prefs.getString),
        AuthCardStyle.values,
        AuthCardStyle.framed,
      );
      final backendUrlMode = _parseEnum(
        readPref<String>(prefs, _backendUrlModeKey, prefs.getString),
        BackendUrlMode.values,
        BackendUrlMode.builtin,
      );
      final colorway = _parseEnum(
        readPref<String>(prefs, _colorwayKey, prefs.getString),
        NotifColorway.values,
        NotifColorway.dusk1,
      );
      final fontSet = _parseEnum(
        readPref<String>(prefs, _fontSetKey, prefs.getString),
        NotifFontSet.values,
        NotifFontSet.current,
      );
      final homeDensity = _parseEnum(
        readPref<String>(prefs, _homeDensityKey, prefs.getString),
        HomeDensity.values,
        HomeDensity.compact,
      );
      final customBackendUrl =
          readPref<String>(prefs, _customBackendUrlKey, prefs.getString) ?? '';

      _designDitheringEnabled = designDitheringEnabled;
      _authCardStyle = authCardStyle;
      _backendUrlMode = backendUrlMode;
      _colorway = colorway;
      _fontSet = fontSet;
      _homeDensity = homeDensity;
      _customBackendUrl = customBackendUrl;
    } catch (e, st) {
      loadError ??= e;
      loadStackTrace ??= st;
      if (kDebugMode) debugPrint('AppSettings._load failed: $e');
    } finally {
      final error = loadError;
      _persistenceError = error == null
          ? null
          : AppSettingsPersistenceException(
              'load',
              error,
              loadStackTrace ?? StackTrace.current,
            );
      _loaded = true;
      notifyListeners();
    }
  }

  /// Try to persist a change; on failure, capture the exception, keep the
  /// in-memory state, and notify listeners. Callers do not need to handle
  /// the future — the error is observable via [persistenceError].
  Future<void> _write(
    String operation,
    Future<bool> Function(SharedPreferences prefs) writer,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await writer(prefs);
      if (!ok) {
        throw StateError('SharedPreferences refused the write');
      }
      if (_persistenceError != null) {
        _persistenceError = null;
        notifyListeners();
      }
    } catch (e, st) {
      _persistenceError = AppSettingsPersistenceException(operation, e, st);
      if (kDebugMode) debugPrint('AppSettings.$operation failed: $e');
      notifyListeners();
    }
  }

  Future<void> setDesignDitheringEnabled(bool enabled) async {
    if (_designDitheringEnabled == enabled) return;
    _designDitheringEnabled = enabled;
    notifyListeners();
    await _write(
      'setDesignDitheringEnabled',
      (prefs) => prefs.setBool(_ditheringKey, enabled),
    );
  }

  Future<void> setAuthCardStyle(AuthCardStyle style) async {
    if (_authCardStyle == style) return;
    _authCardStyle = style;
    notifyListeners();
    await _write(
      'setAuthCardStyle',
      (prefs) => prefs.setString(_authCardStyleKey, style.name),
    );
  }

  Future<void> setBackendUrlMode(BackendUrlMode mode) async {
    if (_backendUrlMode == mode) return;
    _backendUrlMode = mode;
    notifyListeners();
    await _write(
      'setBackendUrlMode',
      (prefs) => prefs.setString(_backendUrlModeKey, mode.name),
    );
  }

  Future<void> setCustomBackendUrl(String url) async {
    final trimmed = url.trim();
    if (_customBackendUrl == trimmed) return;
    _customBackendUrl = trimmed;
    notifyListeners();
    await _write(
      'setCustomBackendUrl',
      (prefs) => prefs.setString(_customBackendUrlKey, trimmed),
    );
  }

  Future<void> setColorway(NotifColorway colorway) async {
    if (_colorway == colorway) return;

    _colorway = colorway;
    notifyListeners();

    await _write(
      'setColorway',
      (prefs) => prefs.setString(_colorwayKey, colorway.name),
    );
  }

  Future<void> setFontSet(NotifFontSet set) async {
    if (_fontSet == set) return;
    _fontSet = set;
    notifyListeners();
    await _write(
      'setFontSet',
      (prefs) => prefs.setString(_fontSetKey, set.name),
    );
  }

  Future<void> setHomeDensity(HomeDensity density) async {
    if (_homeDensity == density) return;
    _homeDensity = density;
    notifyListeners();
    await _write(
      'setHomeDensity',
      (prefs) => prefs.setString(_homeDensityKey, density.name),
    );
  }

  static T _parseEnum<T extends Enum>(String? raw, List<T> values, T fallback) {
    if (raw == null) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    if (kDebugMode) debugPrint('AppSettings: unknown enum value "$raw"');
    return fallback;
  }
}
