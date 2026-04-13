import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthCardStyle { glass, framed }

enum BackendUrlMode {
  /// Use only the built-in compile-time URL.
  builtin,

  /// Try the custom URL first; fall back to the built-in URL on failure.
  customWithFallback,

  /// Use only the custom URL — no fallback.
  customOnly,
}

class AppSettingsController extends ChangeNotifier {
  static const String _ditheringKey = 'designDitheringEnabled';
  static const String _authCardStyleKey = 'debugAuthCardStyle';
  static const String _backendUrlModeKey = 'backendUrlMode';
  static const String _customBackendUrlKey = 'customBackendUrl';

  bool _designDitheringEnabled = true;
  AuthCardStyle _authCardStyle = AuthCardStyle.framed;
  BackendUrlMode _backendUrlMode = BackendUrlMode.builtin;
  String _customBackendUrl = '';

  AppSettingsController() {
    _load();
  }

  bool get designDitheringEnabled => _designDitheringEnabled;
  AuthCardStyle get authCardStyle => _authCardStyle;
  BackendUrlMode get backendUrlMode => _backendUrlMode;
  String get customBackendUrl => _customBackendUrl;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _designDitheringEnabled = prefs.getBool(_ditheringKey) ?? true;
      final rawAuthCardStyle = prefs.getString(_authCardStyleKey);
      _authCardStyle = AuthCardStyle.values.firstWhere(
        (style) => style.name == rawAuthCardStyle,
        orElse: () => AuthCardStyle.framed,
      );
      final rawBackendUrlMode = prefs.getString(_backendUrlModeKey);
      _backendUrlMode = BackendUrlMode.values.firstWhere(
        (mode) => mode.name == rawBackendUrlMode,
        orElse: () => BackendUrlMode.builtin,
      );
      _customBackendUrl = prefs.getString(_customBackendUrlKey) ?? '';
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings._load: $e');
      // SharedPreferences failed (e.g., corrupted storage).
      // Fall back to defaults already set in field initializers.
    }
  }

  Future<void> setDesignDitheringEnabled(bool enabled) async {
    if (_designDitheringEnabled == enabled) {
      return;
    }

    _designDitheringEnabled = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ditheringKey, enabled);
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings.setDesignDitheringEnabled: $e');
    }
  }

  Future<void> setAuthCardStyle(AuthCardStyle style) async {
    if (_authCardStyle == style) {
      return;
    }

    _authCardStyle = style;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authCardStyleKey, style.name);
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings.setAuthCardStyle: $e');
    }
  }

  Future<void> setBackendUrlMode(BackendUrlMode mode) async {
    if (_backendUrlMode == mode) return;
    _backendUrlMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backendUrlModeKey, mode.name);
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings.setBackendUrlMode: $e');
    }
  }

  Future<void> setCustomBackendUrl(String url) async {
    final trimmed = url.trim();
    if (_customBackendUrl == trimmed) return;
    _customBackendUrl = trimmed;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customBackendUrlKey, trimmed);
    } catch (e) {
      if (kDebugMode) debugPrint('AppSettings.setCustomBackendUrl: $e');
    }
  }
}
