import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

const String apiUrl = String.fromEnvironment('API_URL',
    defaultValue: 'http://localhost:8000/api/v1');

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

  Future<void> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$apiUrl/token/'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String accessToken = data['access'] as String;
      final String refreshToken = data['refresh'] as String;
      _jwt = JWT(access: accessToken, refresh: refreshToken);
      notifyListeners();
    } else {
      throw Exception(
          'Failed to log in, response: (${response.statusCode}) ${response.body}');
    }
  }

  void logout() {
    _jwt = null;
    notifyListeners();
  }

  Future<void> register(String username, String email, String password,
      {bool autoLogIn = true}) async {
    final response = await http.post(Uri.parse('$apiUrl/accounts/users/'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          "username": username,
          "email": email,
          "password": password
        }));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Failed to register, response: (${response.statusCode}) ${response.body}');
    }

    if (autoLogIn) {
      return await login(username, password);
    }
  }

  Future<void> refreshToken(String refreshToken) async {
    final response = await http.post(
      Uri.parse('$apiUrl/token/refresh/'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'refresh': refreshToken,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String accessToken = data['access'] as String;
      _jwt = JWT(access: accessToken, refresh: refreshToken);
      notifyListeners();
    } else {
      throw Exception(
          'Failed to refresh token, response: (${response.statusCode}) ${response.body}');
    }
  }

  Future<bool> verifyToken(String token) async {
    final response = await http.post(
      Uri.parse('$apiUrl/token/verify/'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'token': token,
      }),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      return false;
    }
  }

  JWT? get jwt => _jwt;
}

class UserDataService extends ChangeNotifier {
  UserData? _userData;
  // JWT? jwt = context.watch<AuthService>().jwt;
  final AuthService _authService;

  UserDataService(this._authService) {
    _authService.addListener(_handleAuthChange);
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
    if (jwt == null) {
      return;
    }

    final response = await http.get(
      Uri.parse('$apiUrl/accounts/users'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer ${jwt.access}',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String email = data['email'] as String;
      final String username = data['username'] as String;
      final String name = data['name'] as String;
      _userData = UserData(email: email, username: username, name: name);

      notifyListeners();
    } else {
      throw Exception(
          'Failed to fetch user info, response: (${response.statusCode}) ${response.body}');
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChange);
    super.dispose();
  }

  UserData? get userData => _userData;
}
