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
      headers: const {'Content-Type': 'application/json'},
      body: {'username': username, 'password': password},
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      _jwt = JWT(
        access: data['access'] as String,
        refresh: data['refresh'] as String,
      );
      notifyListeners();
    } else {
      throw Exception(
        'Failed to log in, response: (${response.statusCode}) ${response.data}',
      );
    }
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
      headers: const {'Content-Type': 'application/json'},
      body: {'username': username, 'email': email, 'password': password},
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to register, response: (${response.statusCode}) ${response.data}',
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
      headers: const {'Content-Type': 'application/json'},
      body: {'refresh': refreshToken},
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      _jwt = JWT(access: data['access'] as String, refresh: refreshToken);
      notifyListeners();
    } else {
      throw Exception(
        'Failed to refresh token, response: (${response.statusCode}) ${response.data}',
      );
    }
  }

  Future<bool> verifyToken(String token) async {
    final response = await apiPost(
      '/token/verify/',
      settings: _settings,
      headers: const {'Content-Type': 'application/json'},
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
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${jwt.access}',
      },
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      _userData = UserData(
        email: data['email'] as String,
        username: data['username'] as String,
        name: data['name'] as String,
      );
      notifyListeners();
    } else {
      throw Exception(
        'Failed to fetch user info, response: (${response.statusCode}) ${response.data}',
      );
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChange);
    super.dispose();
  }

  UserData? get userData => _userData;
}
