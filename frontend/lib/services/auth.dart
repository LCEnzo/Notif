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

/// Set when a login asks to be remembered, cleared on logout and on a genuine
/// rejection. Lets a cold start tell "this device never had a session"
/// (anonymous) from "the session we had was refused" (expired) — the refresh
/// cookie itself is invisible to us on web, so it cannot answer that question.
const _rememberedSessionKey = 'hasRememberedSession';

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

/// The refresh could not be completed, and not because anything was rejected:
/// the backend is unreachable, restarting, timing out, or behind a failing
/// gateway. Credentials are still presumed valid — this state exists so an
/// outage (a deploy, most often) can never be mistaken for a logout.
final class AuthUnavailable extends AuthState {
  const AuthUnavailable({
    required this.failure,
    required this.hadRememberedSession,
    this.previous,
  });

  /// Why the refresh could not be completed.
  final AppFailure failure;

  /// Access token still held from before the outage, if any. Null after a
  /// cold start that never got one.
  final JWT? previous;

  /// Whether a remembered session is expected to come back once the backend
  /// does — i.e. whether retrying is worth anything.
  final bool hadRememberedSession;

  /// Whether the app should keep retrying on its own.
  bool get isRetryable => failure.isRetryable;
}

final class AuthExpired extends AuthState {
  const AuthExpired();
}

final class AuthLoggingOut extends AuthState {
  const AuthLoggingOut();
}

/// Resolves the backend origin when it cannot carry the session cookie.
/// Injectable so the browser-only condition is testable off-browser.
typedef CrossSiteBackendProbe =
    String? Function(AppSettingsController? settings);

class AuthService extends ChangeNotifier {
  AuthService({
    bool restoreSessionOnStart = false,
    List<Duration>? recoveryBackoff,
    CrossSiteBackendProbe? crossSiteBackendProbe,
  }) : _restoreSessionOnStart = restoreSessionOnStart,
       _recoveryBackoff = recoveryBackoff ?? defaultRecoveryBackoff,
       _crossSiteBackendProbe = crossSiteBackendProbe ?? crossSiteBackendOrigin,
       // Starting in "restoring" keeps the router on a splash instead of
       // flashing the login screen before the remembered session lands.
       _state = restoreSessionOnStart
           ? const AuthRestoring()
           : const AuthAnonymous() {
    _configureApiAuth();
  }

  /// Delay before each automatic recovery attempt while the backend is
  /// unreachable. Length doubles as the attempt budget: after the last entry
  /// the app waits for the user (or a settings change) instead of polling
  /// forever. Sized to cover a deploy or a container restart.
  static const List<Duration> defaultRecoveryBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
  ];

  AuthState _state;
  AppSettingsController? _settings;
  final bool _restoreSessionOnStart;
  final List<Duration> _recoveryBackoff;
  final CrossSiteBackendProbe _crossSiteBackendProbe;
  Future<void>? _restoreSessionFuture;
  Future<String?>? _refreshInFlight;
  Timer? _recoveryTimer;
  int _recoveryAttempt = 0;
  int _authEpoch = 0;
  bool _restoreAttempted = false;
  bool _disposed = false;
  String? _sessionDiagnostic;

  void updateSettings(AppSettingsController? settings) {
    final changed = !identical(_settings, settings);
    _settings = settings;
    _configureApiAuth();
    if (_restoreSessionOnStart && !_restoreAttempted) {
      _restoreAttempted = true;
      unawaited(restoreRememberedSession());
      return;
    }
    // A settings change is a user action and a fresh chance for the backend to
    // be reachable — spend a new recovery budget on it.
    if (changed && _state is AuthUnavailable) {
      _recoveryAttempt = 0;
      _scheduleRecoveryAttempt();
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
    final hadRememberedSession =
        previous != null || await _hasRememberedSession();
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

      _recoveryAttempt = 0;
      _sessionDiagnostic = null;
      _setState(AuthAuthenticated(JWT(access: accessToken)));
      return accessToken;
    } on Exception catch (error) {
      final failure = AppFailure.from(error, endpoint: 'POST /token/refresh/');
      if (kDebugMode) {
        debugPrint('AuthService._refreshAccessToken: ${failure.debugMessage}');
      }
      if (epoch != _authEpoch) {
        // A newer login or logout already decided what the session is; this is
        // the answer to a question nobody is asking any more.
        return null;
      }

      if (failure.isAuthRejection) {
        await _handleRejectedSession(hadRememberedSession);
      } else {
        // Unreachable, timing out, 502 from the gateway mid-deploy: the
        // credentials were never judged, so they stay.
        _setState(
          AuthUnavailable(
            failure: failure,
            previous: previous,
            hadRememberedSession: hadRememberedSession,
          ),
        );
        if (failure.isRetryable) {
          _scheduleRecoveryAttempt();
        }
      }
      return null;
    }
  }

  /// The server refused the refresh credentials. Only here is ending the
  /// session correct.
  Future<void> _handleRejectedSession(bool hadRememberedSession) async {
    _diagnoseCrossSiteCookie();
    await _setRememberedSession(false);
    _setState(
      hadRememberedSession ? const AuthExpired() : const AuthAnonymous(),
    );
  }

  /// A cross-site backend URL on web makes remember-me structurally
  /// impossible: the browser will not attach the `SameSite=Lax` refresh cookie
  /// to a request going to another site, so every refresh looks like a
  /// rejection. Without this the only trace was a debug print.
  void _diagnoseCrossSiteCookie() {
    final crossSiteOrigin = _crossSiteBackendProbe(_settings);
    if (crossSiteOrigin == null) {
      return;
    }
    _sessionDiagnostic =
        'Staying signed in is not possible with a cross-site backend '
        '($crossSiteOrigin): the browser refuses to send the session cookie '
        'to a different site than the one serving the app. Use a same-origin '
        'backend URL, or expect to sign in again after every reload.';
    if (kDebugMode) {
      debugPrint('AuthService: $_sessionDiagnostic');
    }
  }

  void _scheduleRecoveryAttempt() {
    if (_disposed || _recoveryTimer != null) {
      return;
    }
    if (_recoveryAttempt >= _recoveryBackoff.length) {
      if (kDebugMode) {
        debugPrint(
          'AuthService: automatic recovery paused after $_recoveryAttempt '
          'attempts — waiting for a manual retry',
        );
      }
      return;
    }

    final delay = _recoveryBackoff[_recoveryAttempt];
    _recoveryAttempt += 1;
    _recoveryTimer = Timer(delay, () {
      _recoveryTimer = null;
      unawaited(_attemptRecovery());
    });
  }

  Future<void> _attemptRecovery() async {
    if (_disposed || _state is! AuthUnavailable) {
      return;
    }

    if (!await _isBackendReachable()) {
      if (!_disposed && _state is AuthUnavailable) {
        _scheduleRecoveryAttempt();
      }
      return;
    }

    await _refreshAccessToken();
    if (!_disposed && _state is AuthUnavailable) {
      _scheduleRecoveryAttempt();
    }
  }

  /// Liveness probe, so recovery does not spend refresh attempts on a backend
  /// that is still down.
  Future<bool> _isBackendReachable() async {
    try {
      final response = await apiGet(
        healthPath,
        settings: _settings,
        headers: _jsonHeaders,
      );
      return response.statusCode == 200;
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService._isBackendReachable: $error');
      }
      return false;
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
    _cancelRecovery();
    _sessionDiagnostic = null;
    _setState(AuthAuthenticated(JWT(access: access)));
    await _setRememberedSession(rememberMe);
    await persistLastSuccessfulUsername(username);
  }

  Future<void> logout() async {
    _authEpoch += 1;
    _cancelRecovery();
    _sessionDiagnostic = null;
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
      await _setRememberedSession(false);
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

  Future<void> refreshToken() async {
    final accessToken = await _refreshAccessToken();
    if (accessToken == null) {
      // Surface the classified failure so a caller can tell an outage (retry)
      // from a rejection (sign in again) without parsing a string.
      throw sessionUnavailableFailure ??
          const AppFailure(
            category: FailureCategory.unauthorized,
            message: 'Sign in again to continue.',
          );
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
      // An outage does not invalidate the token we already hold.
      AuthUnavailable(:final previous) => previous,
      _ => null,
    };
  }

  int? get currentUserId => jwt?.userId;
  bool get isRestoringSession => _state is AuthRestoring;

  /// Why the app cannot currently reach the session, when that is the case.
  /// Retryable by definition — [retryRememberedSession] is the action.
  AppFailure? get sessionUnavailableFailure => switch (_state) {
    AuthUnavailable(:final failure) => failure,
    _ => null,
  };

  /// A configuration problem that makes staying signed in impossible, phrased
  /// for the user. Survives until the next successful sign-in.
  String? get sessionDiagnostic => _sessionDiagnostic;

  /// Whether an automatic recovery attempt is pending.
  bool get isRecoveryScheduled => _recoveryTimer != null;

  Future<void> restoreRememberedSession() {
    final existing = _restoreSessionFuture;
    if (existing != null) {
      return existing;
    }

    final future = _restoreRememberedSession();
    _restoreSessionFuture = future;
    return future;
  }

  /// Re-attempts a session restore after it failed for a non-auth reason.
  ///
  /// The automatic attempt latches, so without this a single outage at launch
  /// left the app signed out for the whole process lifetime even though the
  /// refresh cookie stayed valid for days.
  Future<void> retryRememberedSession() {
    _cancelRecovery();
    _recoveryAttempt = 0;
    return restoreRememberedSession();
  }

  Future<void> _restoreRememberedSession() async {
    _setState(const AuthRestoring());
    try {
      await _settings?.initialized;
      if (!await _hasRememberedSession()) {
        // Nothing to restore: a first-time visitor is anonymous, not expired.
        // Also avoids a guaranteed-401 request on every first launch.
        return;
      }
      await _refreshAccessToken();
    } finally {
      _restoreSessionFuture = null;
      if (_state is AuthRestoring) {
        _setState(const AuthAnonymous());
      }
    }
  }

  Future<bool> _hasRememberedSession() async {
    try {
      final store = await PreferenceStore.load();
      return store.read<bool>(_rememberedSessionKey) ?? false;
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService._hasRememberedSession: $error');
      }
      return false;
    }
  }

  Future<void> _setRememberedSession(bool remembered) async {
    try {
      final store = await PreferenceStore.load();
      if (remembered) {
        await store.writeBool(_rememberedSessionKey, true);
      } else {
        await store.remove(_rememberedSessionKey);
      }
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService._setRememberedSession: $error');
      }
    }
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  void _setState(AuthState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRecovery();
    super.dispose();
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
