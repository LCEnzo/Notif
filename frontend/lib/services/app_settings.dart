import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthCardStyle { glass, framed }

class AppSettingsController extends ChangeNotifier {
  static const String _ditheringKey = 'designDitheringEnabled';
  static const String _authCardStyleKey = 'debugAuthCardStyle';

  bool _designDitheringEnabled = false;
  AuthCardStyle _authCardStyle = AuthCardStyle.framed;

  AppSettingsController() {
    _load();
  }

  bool get designDitheringEnabled => _designDitheringEnabled;
  AuthCardStyle get authCardStyle => _authCardStyle;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _designDitheringEnabled = prefs.getBool(_ditheringKey) ?? false;
      final rawAuthCardStyle = prefs.getString(_authCardStyleKey);
      _authCardStyle = AuthCardStyle.values.firstWhere(
        (style) => style.name == rawAuthCardStyle,
        orElse: () => AuthCardStyle.framed,
      );
      notifyListeners();
    } catch (_) {
      // Widget tests and unsupported platforms can fall back to defaults.
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
    } catch (_) {
      // Ignore persistence failures and keep the in-memory value.
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
    } catch (_) {
      // Ignore persistence failures and keep the in-memory value.
    }
  }
}
