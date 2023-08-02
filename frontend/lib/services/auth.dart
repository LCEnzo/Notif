import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String apiUrl = 'http://localhost:8000';

  Future<void> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$apiUrl/login/'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      // TODO: Handle success - save JWT token
    } else {
      // TODO: Handle error
    }
  }

  Future<void> logout(String username, String password) async {
    // TODO
  }

  Future<void> register(String username, String password) async {
    // TODO
  }
}
