import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserData {
  String email;
  String username;
  String name;

  UserData({required this.email, required this.username, required this.name});
}

class JWT {
  String access;
  String refresh;

  JWT({required this.access, required this.refresh});

  int? get userId => _decodeJwtUserId(access);
}

const _jsonHeaders = {'Content-Type': 'application/json'};
const _lastSuccessfulUsernameKey = 'lastSuccessfulUsername';

class AuthService extends ChangeNotifier {
  AuthService() {
    _configureApiAuth();
  }

  JWT? _jwt;
  AppSettingsController? _settings;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
    _configureApiAuth();
  }

  void _configureApiAuth() {
    configureApiAuth(
      accessTokenReader: () => _jwt?.access,
      refreshTokenReader: () => _jwt?.refresh,
      refreshAccessToken: _refreshAccessToken,
      authExpiredHandler: _handleAuthExpired,
    );
  }

  Future<void> _handleAuthExpired() async {
    if (_jwt == null) {
      return;
    }

    _jwt = null;
    notifyListeners();
  }

  Future<String?> _refreshAccessToken(String refreshToken) async {
    try {
      final response = await apiPost(
        "/token/refresh/",
        settings: _settings,
        headers: _jsonHeaders,
        body: {"refresh": refreshToken},
      );
      final data = expectSuccessJson(response, "Token refresh");
      final accessToken = (data["access"] as String?)?.trim();
      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      _jwt = JWT(access: accessToken, refresh: refreshToken);
      notifyListeners();
      return accessToken;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService._refreshAccessToken: $error');
      }
      return null;
    }
  }

  Future<void> login(String username, String password) async {
    final response = await apiPost(
      '/token/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {'username': username, 'password': password},
    );
    final data = expectSuccessJson(response, 'Login');
    _jwt = JWT(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
    );
    await persistLastSuccessfulUsername(username);
    notifyListeners();
  }

  void logout() {
    _jwt = null;
    notifyListeners();
  }

  Future<void> register(
    String username,
    String email,
    String password, {
    bool autoLogIn = true,
  }) async {
    final response = await apiPost(
      '/accounts/users/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {'username': username, 'email': email, 'password': password},
    );

    // Registration may return 200 or 201.
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Registration failed: (${response.statusCode}) ${response.data}',
      );
    }

    if (autoLogIn) {
      return await login(username, password);
    }
  }

  Future<void> refreshToken(String refreshToken) async {
    final accessToken = await _refreshAccessToken(refreshToken);
    if (accessToken == null) {
      throw Exception('Token refresh failed.');
    }
  }

  Future<bool> verifyToken(String token) async {
    final response = await apiPost(
      '/token/verify/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {'token': token},
    );
    return response.statusCode == 200;
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await apiPost(
      '/accounts/password/reset/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {'email': email.trim().toLowerCase()},
    );
    expectSuccessJson(response, 'Password reset request');
  }

  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    final response = await apiPost(
      '/accounts/password/reset/confirm/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'new_password': newPassword,
      },
    );
    expectSuccessJson(response, 'Password reset confirm');
  }

  JWT? get jwt => _jwt;
  int? get currentUserId => _jwt?.userId;
}

class UserDataService extends ChangeNotifier {
  UserData? _userData;
  final AuthService _authService;
  AppSettingsController? _settings;

  UserDataService(this._authService) {
    _authService.addListener(_handleAuthChange);
  }

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  void _handleAuthChange() async {
    final jwt = _authService.jwt;
    if (jwt != null) {
      await getUserInfo(notifyOnComplete: false);
    } else {
      _userData = null;
    }
    notifyListeners();
  }

  Future<void> getUserInfo({bool notifyOnComplete = true}) async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      if (notifyOnComplete) {
        notifyListeners();
      }
      return;
    }

    try {
      final response = await apiGet(
        '/accounts/users/get_my_info/',
        settings: _settings,
        headers: {..._jsonHeaders, 'Authorization': 'Bearer ${jwt.access}'},
      );
      final data = expectSuccessJson(response, 'Fetch user info');
      _userData = UserData(
        email: data['email'] as String,
        username: data['username'] as String,
        name: data['name'] as String,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('UserDataService.getUserInfo: $error');
      }
    } finally {
      if (notifyOnComplete) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChange);
    super.dispose();
  }

  UserData? get userData => _userData;
}

int? _decodeJwtUserId(String token) {
  final parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }

  try {
    final payloadJson = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final payload = jsonDecode(payloadJson);
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final dynamic rawUserId =
        payload['user_id'] ?? payload['userId'] ?? payload['sub'];

    if (rawUserId is int) {
      return rawUserId;
    }
    if (rawUserId is String) {
      return int.tryParse(rawUserId);
    }
  } catch (error) {
    if (kDebugMode) {
      debugPrint('AuthService._decodeJwtUserId: $error');
    }
  }

  return null;
}

Future<void> persistLastSuccessfulUsername(String username) async {
  final normalized = username.trim();
  if (normalized.isEmpty) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastSuccessfulUsernameKey, normalized);
}

Future<String?> loadLastSuccessfulUsername() async {
  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getString(_lastSuccessfulUsernameKey);
  if (current != null && current.trim().isNotEmpty) {
    return current.trim();
  }

  final legacy = prefs.getString('username');
  if (legacy != null && legacy.trim().isNotEmpty) {
    final normalized = legacy.trim();
    await prefs.setString(_lastSuccessfulUsernameKey, normalized);
    await prefs.remove('username');
    return normalized;
  }

  return null;
}
