import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';

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
}

const _jsonHeaders = {'Content-Type': 'application/json'};

class AuthService extends ChangeNotifier {
  JWT? _jwt;
  AppSettingsController? _settings;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
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
    final response = await apiPost(
      '/token/refresh/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {'refresh': refreshToken},
    );
    final data = expectSuccessJson(response, 'Token refresh');
    _jwt = JWT(access: data['access'] as String, refresh: refreshToken);
    notifyListeners();
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

  JWT? get jwt => _jwt;
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
    JWT? jwt = _authService.jwt;
    if (jwt != null) {
      await getUserInfo();
    } else {
      _userData = null;
    }
    notifyListeners();
  }

  Future<void> getUserInfo() async {
    JWT? jwt = _authService.jwt;
    if (jwt == null) return;

    final response = await apiGet(
      '/accounts/users/get_my_info/',
      settings: _settings,
      headers: {
        ..._jsonHeaders,
        'Authorization': 'Bearer ${jwt.access}',
      },
    );
    final data = expectSuccessJson(response, 'Fetch user info');
    _userData = UserData(
      email: data['email'] as String,
      username: data['username'] as String,
      name: data['name'] as String,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChange);
    super.dispose();
  }

  UserData? get userData => _userData;
}
