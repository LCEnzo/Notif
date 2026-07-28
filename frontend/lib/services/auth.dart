import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/json_contracts.dart';
import 'package:notif/services/persistence.dart';
import 'package:notif/services/refresh_cookie_store.dart';

class UserData {
  UserData({
    required this.email,
    required this.username,
    required this.name,
    required this.isStaff,
    required this.isSuperuser,
  });

  factory UserData.fromJson(JsonCursor json) {
    return UserData(
      email: json.field('email').string(),
      username: json.field('username').string(allowEmpty: false),
      name: json.field('name').string(),
      isStaff: json.field('is_staff').boolean(),
      isSuperuser: json.field('is_superuser').boolean(),
    );
  }

  String email;
  String username;
  String name;
  bool isStaff;
  bool isSuperuser;
}

class JWT {
  JWT({required this.access});
  final String access;

  int? get userId => _decodeJwtUserId(access);
}

const _jsonHeaders = {'Content-Type': 'application/json'};
const _refreshHeaders = {
  'Content-Type': 'application/json',
  'X-Refresh-Request': '1',
};
const _lastSuccessfulUsernameKey = 'lastSuccessfulUsername';

sealed class AuthState {
  const AuthState();
}

final class AuthAnonymous extends AuthState {
  const AuthAnonymous();
}

final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.jwt);

  final JWT jwt;
}

final class AuthRefreshing extends AuthState {
  const AuthRefreshing(this.previous);

  final JWT previous;
}

final class AuthExpired extends AuthState {
  const AuthExpired();
}

final class AuthLoggingOut extends AuthState {
  const AuthLoggingOut();
}

class AuthService extends ChangeNotifier {
  AuthService({bool restoreSessionOnStart = false})
    : _restoreSessionOnStart = restoreSessionOnStart {
    _configureApiAuth();
  }

  AuthState _state = const AuthAnonymous();
  AppSettingsController? _settings;
  final bool _restoreSessionOnStart;
  Future<void>? _restoreSessionFuture;
  Future<String?>? _refreshInFlight;
  int _authEpoch = 0;
  bool _restoreAttempted = false;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
    _configureApiAuth();
    if (_restoreSessionOnStart && !_restoreAttempted) {
      _restoreAttempted = true;
      unawaited(restoreRememberedSession());
    }
  }

  void _configureApiAuth() {
    configureApiAuth(
      accessTokenReader: () => jwt?.access,
      refreshAccessToken: _refreshAccessToken,
    );
  }

  Future<String?> _refreshAccessToken() async {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }

    final epoch = _authEpoch;
    final previous = jwt;
    if (previous != null && _state is! AuthRestoring) {
      _setState(AuthRefreshing(previous));
    }

    final refresh = _performRefresh(epoch, previous);
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<String?> _performRefresh(int epoch, JWT? previous) async {
    try {
      final response = await apiPost(
        "/token/refresh/",
        settings: _settings,
        headers: _refreshHeaders,
        body: const <String, Object?>{},
      );
      final data = expectSuccessObject(response, "Token refresh");
      final accessToken = data.field("access").string(allowEmpty: false);
      if (epoch != _authEpoch) {
        return null;
      }

      _setState(AuthAuthenticated(JWT(access: accessToken)));
      return accessToken;
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService._refreshAccessToken: $error');
      }
      if (epoch != _authEpoch) {
        return null;
      }

      final failure = AppFailure.from(error, endpoint: '/token/refresh/');
      if (previous != null && failure.isAuthRejection) {
        // The server looked at the refresh cookie and said no. Only this is
        // proof the session died.
        _setState(const AuthExpired());
      } else if (previous != null) {
        // A timeout or unreachable server says nothing about the session.
        // Keep it; the next 401 will try the refresh again.
        _setState(AuthAuthenticated(previous));
      } else if (_state is AuthRestoring) {
        // A cold start that cannot refresh is simply not signed in. This is
        // where a fresh install lands, and it never had a session to expire.
        _setState(const AuthAnonymous());
      }
      return null;
    }
  }

  Future<void> loginWithRememberMe(
    String username,
    String password, {
    required bool rememberMe,
  }) async {
    final response = await apiPost(
      '/token/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {
        'username': username,
        'password': password,
        'remember_me': rememberMe,
      },
    );
    final data = expectSuccessObject(response, 'Login');
    final access = data.field('access').string(allowEmpty: false);
    _authEpoch += 1;
    _setState(AuthAuthenticated(JWT(access: access)));
    await persistLastSuccessfulUsername(username);
  }

  Future<void> logout() async {
    _authEpoch += 1;
    _setState(const AuthLoggingOut());
    try {
      await apiPost(
        '/token/logout/',
        settings: _settings,
        headers: _jsonHeaders,
        body: const <String, Object?>{},
      );
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService.logout: $error');
      }
    } finally {
      await clearNativeRefreshCookies();
      _setState(const AuthAnonymous());
    }
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
      return loginWithRememberMe(username, password, rememberMe: true);
    }
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await apiPost(
      '/accounts/password/reset/',
      settings: _settings,
      headers: _jsonHeaders,
      body: {'email': email.trim().toLowerCase()},
    );
    expectSuccessObject(response, 'Password reset request');
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
    expectSuccessObject(response, 'Password reset confirm');
  }

  AuthState get state => _state;
  JWT? get jwt {
    return switch (_state) {
      AuthAuthenticated(:final jwt) => jwt,
      AuthRefreshing(:final previous) => previous,
      _ => null,
    };
  }

  int? get currentUserId => jwt?.userId;
  bool get isRestoringSession => _state is AuthRestoring;

  Future<void> restoreRememberedSession() {
    final existing = _restoreSessionFuture;
    if (existing != null) {
      return existing;
    }

    final future = _restoreRememberedSession();
    _restoreSessionFuture = future;
    return future;
  }

  Future<void> _restoreRememberedSession() async {
    _setState(const AuthRestoring());
    try {
      await _settings?.initialized;
      await _refreshAccessToken();
    } finally {
      _restoreSessionFuture = null;
      if (_state is AuthRestoring) {
        _setState(const AuthAnonymous());
      }
    }
  }

  void _setState(AuthState state) {
    _state = state;
    notifyListeners();
  }
}

class UserDataService extends ChangeNotifier {
  UserDataService(this._authService) {
    _authService.addListener(_handleAuthChange);
  }
  UserData? _userData;
  final AuthService _authService;
  AppSettingsController? _settings;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  Future<void> _handleAuthChange() async {
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
      final data = expectSuccessObject(response, 'Fetch user info');
      _userData = UserData.fromJson(data);
    } on Exception catch (error) {
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
    if (payload is! Map<Object?, Object?>) {
      return null;
    }

    final rawUserId = payload['user_id'] ?? payload['userId'] ?? payload['sub'];

    if (rawUserId is int) {
      return rawUserId;
    }
    if (rawUserId is String) {
      return int.tryParse(rawUserId);
    }
  } on Exception catch (error) {
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

  final store = await PreferenceStore.load();
  await store.writeString(_lastSuccessfulUsernameKey, normalized);
}

Future<String?> loadLastSuccessfulUsername() async {
  final store = await PreferenceStore.load();
  final current = store.read<String>(_lastSuccessfulUsernameKey);
  if (current != null && current.trim().isNotEmpty) {
    return current.trim();
  }

  final legacy = store.read<String>('username');
  if (legacy != null && legacy.trim().isNotEmpty) {
    final normalized = legacy.trim();
    await store.writeString(_lastSuccessfulUsernameKey, normalized);
    await store.remove('username');
    return normalized;
  }

  return null;
}
