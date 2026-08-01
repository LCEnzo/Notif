import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserData {
  UserData({
    required this.id,
    required this.email,
    required this.username,
    required this.name,
    required this.isStaff,
    required this.isSuperuser,
  });

  factory UserData.fromJson(Map<String, dynamic> json) => UserData(
    id: json['id'] as int?,
    email: json['email'] as String? ?? '',
    username: json['username'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isStaff: json['is_staff'] == true,
    isSuperuser: json['is_superuser'] == true,
  );

  /// Needed by account-resource endpoints. Nullable because an opaque token
  /// carries no claims — this arrives with the designated identity probe.
  int? id;
  String email;
  String username;
  String name;
  bool isStaff;
  bool isSuperuser;
}

/// How this build presents its session. One transport per platform, chosen at
/// compile time rather than configured: a native app wants a bearer secret in
/// the keystore, a browser wants a cookie it cannot read.
enum SessionTransport {
  cookie,
  bearer
  ;

  String get wireValue => name;
}

SessionTransport get platformTransport =>
    kIsWeb ? SessionTransport.cookie : SessionTransport.bearer;

/// A short, non-identifying label for the devices list.
///
/// Deliberately coarse: the point is to let a human recognise which row to
/// revoke, not to fingerprint the machine.
String defaultDeviceLabel() {
  if (kIsWeb) {
    return 'Browser';
  }
  return defaultTargetPlatform.name[0].toUpperCase() +
      defaultTargetPlatform.name.substring(1);
}

/// The auth states, and only these. Every field a state needs travels with it,
/// so there is no "authenticated but user is null" to defend against.
@immutable
sealed class AuthState {
  const AuthState();
}

/// No credential, and we know it.
class AuthAnonymous extends AuthState {
  const AuthAnonymous();
}

/// A cold-start probe is in flight.
class AuthRestoring extends AuthState {
  const AuthRestoring();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final UserData user;
}

/// The server could not be reached. Distinct from Anonymous on purpose: an
/// outage must not present as "you are signed out", because the credential may
/// be perfectly good.
class AuthUnavailable extends AuthState {
  const AuthUnavailable(this.reason);

  final String reason;
}

/// The app's own configuration prevents asking the server anything: no backend
/// URL is set, or the configured one is refused before a request goes out.
/// Distinct from [AuthUnavailable] because retrying cannot heal it — the only
/// exit is a settings change, so the UI must offer a way to make one.
class AuthConfigError extends AuthState {
  const AuthConfigError(this.reason);

  final String reason;
}

/// The server told us, on a request we meant to authenticate, that the session
/// is over. The only path from Authenticated to signed-out that is not a
/// deliberate logout.
class AuthExpired extends AuthState {
  const AuthExpired();
}

class AuthLoggingOut extends AuthState {
  const AuthLoggingOut();
}

class LogoutRefusedException implements Exception {
  const LogoutRefusedException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String _lastSuccessfulUsernameKey = 'lastSuccessfulUsername';

/// Legacy preference keys from the JWT-era client, removed on first run.
const List<String> _legacyPreferenceKeys = [
  'refreshToken',
  'accessToken',
  'rememberMe',
];

const int _defaultMaxRecoveryProbes = 6;
const Duration _defaultRecoveryInitialDelay = Duration(seconds: 2);
const Duration _defaultRecoveryMaxDelay = Duration(seconds: 30);

class AuthService extends ChangeNotifier {
  AuthService({
    SessionStore? store,
    SessionTransport? transport,
    int maxRecoveryProbes = _defaultMaxRecoveryProbes,
    Duration recoveryInitialDelay = _defaultRecoveryInitialDelay,
    Duration recoveryMaxDelay = _defaultRecoveryMaxDelay,
  }) : assert(maxRecoveryProbes >= 0, 'Recovery probes cannot be negative.'),
       assert(
         !recoveryInitialDelay.isNegative,
         'The initial recovery delay cannot be negative.',
       ),
       assert(
         !recoveryMaxDelay.isNegative,
         'The maximum recovery delay cannot be negative.',
       ),
       _maxRecoveryProbes = maxRecoveryProbes,
       _recoveryInitialDelay = recoveryInitialDelay,
       _recoveryMaxDelay = recoveryMaxDelay,
       _store = store ?? createSessionStore(),
       _transport = transport ?? platformTransport {
    configureApiAuth(
      credentialReader: () => _credential,
      generationReader: () => _generation,
      sessionEndReporter: (error, {required generation}) => unawaited(
        reportPossibleSessionEnd(error, generation: generation),
      ),
    );
  }

  final SessionStore _store;
  final SessionTransport _transport;
  final int _maxRecoveryProbes;
  final Duration _recoveryInitialDelay;
  final Duration _recoveryMaxDelay;

  AppSettingsController? _settings;
  AuthState _state = const AuthRestoring();

  /// Native only. On web this stays null and the browser holds the cookie —
  /// the client keeps no shadow of credential state, so none can drift.
  SessionCredential? _credential;

  /// Monotonic. Every response carries the generation it was issued under, and
  /// anything stale is ignored: a slow 401 from before a logout/login must not
  /// tear down the session that replaced it.
  int _generation = 0;

  /// One auth mutation at a time within this runtime. Across browser tabs there
  /// is deliberately no lock and no compensation — the outcome of concurrent
  /// tab operations is whatever the server committed last, and the sessions
  /// screen is where you notice and fix it.
  Future<void> _mutations = Future<void>.value();

  Timer? _recoveryTimer;
  int _recoveryAttempts = 0;
  int _recoveryEpoch = 0;

  /// Surfaced to the UI when a local credential delete failed. Claiming a
  /// durable sign-out that a later cold start undoes is worse than saying so.
  String? _credentialWarning;

  AuthState get state => _state;
  SessionTransport get transport => _transport;
  String? get credentialWarning => _credentialWarning;

  bool get isAuthenticated => _state is AuthAuthenticated;
  bool get isRestoring => _state is AuthRestoring;

  /// Auth state is not yet known — a probe is in flight, the server could not
  /// be reached to answer one, or the app's configuration prevents asking.
  /// Deliberately *not* the same as anonymous: the credential may be perfectly
  /// good, and rendering a login form here would assert something no one has
  /// established.
  bool get isUndecided =>
      _state is AuthRestoring ||
      _state is AuthUnavailable ||
      _state is AuthConfigError ||
      _state is AuthLoggingOut;
  UserData? get userData => switch (_state) {
    AuthAuthenticated(:final user) => user,
    _ => null,
  };
  int? get currentUserId => userData?.id;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  void _transitionTo(AuthState next) {
    // Re-entering the state you are already in is not a transition. Notifying
    // anyway is how `restore()` — called from initState, where the initial
    // state is already Restoring — ends up marking widgets dirty mid-build.
    if (identical(_state, next)) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  // ── cold start ─────────────────────────────────────────────

  /// The one designated request that establishes auth state at startup.
  ///
  /// Native: only runs when a keystore record exists — its existence *is* the
  /// restoration intent. Web: always runs, because the cookie is invisible to
  /// JS and asking the server is the only way to learn whether one is held.
  /// An anonymous web cold start therefore costs exactly one 401.
  Future<void> restore() async {
    _stopRecovery(resetAttempts: true);
    if (_transport == SessionTransport.bearer) {
      unawaited(_deleteLegacyCredentials());
    }
    await _restore(
      announceRestoring: true,
      startRecoveryOnFailure: true,
    );
  }

  Future<void> _restore({
    required bool announceRestoring,
    required bool startRecoveryOnFailure,
  }) async {
    final generation = _generation;
    if (announceRestoring) {
      _transitionTo(const AuthRestoring());
    }

    if (_transport == SessionTransport.bearer) {
      try {
        _credential = await _store.read();
      } on SessionStoreException catch (error) {
        _credential = null;
        if (generation == _generation) {
          _credentialWarning = error.toString();
          _enterUnavailable(
            'The stored session could not be read: $error',
            startRecovery: startRecoveryOnFailure,
          );
        }
        return;
      }

      if (_credential == null) {
        if (generation == _generation) _transitionTo(const AuthAnonymous());
        return;
      }
    }

    await _probe(
      generation,
      startRecoveryOnFailure: startRecoveryOnFailure,
    );
  }

  /// `GET /accounts/users/get_my_info/`, treated as designated session-bearing.
  ///
  /// Three outcomes and no others: 200 authenticates, our own 401 ends the
  /// session, anything else is an outage rather than a verdict.
  Future<void> _probe(
    int generation, {
    required bool startRecoveryOnFailure,
  }) async {
    try {
      final response = await apiGet(
        '/accounts/users/get_my_info/',
        settings: _settings,
        headers: jsonHeaders,
      );
      final data = expectSuccessJson(response, 'Restore session');
      if (generation != _generation) return;
      _transitionTo(AuthAuthenticated(UserData.fromJson(data)));
    } on DioException catch (error) {
      if (generation != _generation) return;
      if (isSessionChallenge(error.response)) {
        await _forgetCredential();
        if (generation != _generation) return;
        _transitionTo(const AuthAnonymous());
        return;
      }
      _enterUnavailable(
        _describe(error),
        startRecovery: startRecoveryOnFailure,
      );
    } on Exception catch (error) {
      if (generation != _generation) return;
      if (_isConfigError(error)) {
        _enterConfigError(_describe(error));
        return;
      }
      _enterUnavailable(
        _describe(error),
        startRecovery: startRecoveryOnFailure,
      );
    }
  }

  void _enterUnavailable(String reason, {required bool startRecovery}) {
    _transitionTo(AuthUnavailable(reason));
    if (startRecovery) {
      _startRecovery();
    }
  }

  void _enterConfigError(String reason) {
    // The refusal is computed locally and deterministic; a recovery timer
    // would burn its whole probe budget repeating it. Only a settings change
    // exits this state, so any pending recovery dies here too.
    _stopRecovery(resetAttempts: true);
    _transitionTo(AuthConfigError(reason));
  }

  void _startRecovery() {
    _stopRecovery(resetAttempts: true);
    final epoch = _recoveryEpoch;
    _scheduleRecoveryProbe(epoch);
  }

  void _scheduleRecoveryProbe(int epoch) {
    if (_recoveryAttempts >= _maxRecoveryProbes || epoch != _recoveryEpoch) {
      return;
    }
    final delayMs = math.min(
      _recoveryInitialDelay.inMilliseconds << _recoveryAttempts,
      _recoveryMaxDelay.inMilliseconds,
    );
    _recoveryTimer = Timer(
      Duration(milliseconds: delayMs),
      () => unawaited(_runRecoveryProbe(epoch)),
    );
  }

  Future<void> _runRecoveryProbe(int epoch) async {
    if (epoch != _recoveryEpoch || _state is! AuthUnavailable) {
      return;
    }
    await _restore(
      announceRestoring: false,
      startRecoveryOnFailure: false,
    );
    if (epoch != _recoveryEpoch || _state is! AuthUnavailable) {
      return;
    }
    _recoveryAttempts += 1;
    _scheduleRecoveryProbe(epoch);
  }

  void _stopRecovery({bool resetAttempts = false}) {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryEpoch += 1;
    if (resetAttempts) {
      _recoveryAttempts = 0;
    }
  }

  Future<void> retryNow() async {
    if (_state is! AuthUnavailable && _state is! AuthConfigError) {
      return;
    }
    await restore();
  }

  /// Report a 401 seen on a request the app issued while authenticated.
  ///
  /// Ends the session only when all three hold: the response is a 401, it
  /// carries our challenge header, and it was issued under the current
  /// generation. Anything else leaves auth state alone — an edge 401 is a
  /// request-level failure, not a verdict on the credential.
  Future<void> reportPossibleSessionEnd(
    Object error, {
    required int generation,
  }) async {
    if (generation != _generation || _state is! AuthAuthenticated) {
      return;
    }
    if (error is! DioException || !isSessionChallenge(error.response)) {
      return;
    }

    await _forgetCredential();
    if (generation != _generation) return;
    _transitionTo(const AuthExpired());
  }

  /// Snapshot to pass to [reportPossibleSessionEnd] alongside a request.
  int get generation => _generation;

  // ── login / logout ─────────────────────────────────────────

  /// Serialize auth mutations so a login and a logout in the same runtime
  /// cannot interleave and leave the app disagreeing with the server.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    // Keep the chain alive even when an action throws, or one failed login
    // would deadlock every later mutation.
    _mutations = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> login(
    String username,
    String password, {
    String deviceLabel = '',
  }) => _serialized(() => _login(username, password, deviceLabel));

  Future<void> _login(
    String username,
    String password,
    String deviceLabel,
  ) async {
    _stopRecovery(resetAttempts: true);
    _generation++;
    final generation = _generation;
    _credentialWarning = null;

    final response = await apiPost(
      '/auth/login/',
      settings: _settings,
      headers: jsonHeaders,
      fallbackPolicy: FallbackPolicy.never,
      body: {
        'username': username,
        'password': password,
        'transport': _transport.wireValue,
        if (deviceLabel.trim().isNotEmpty) 'device_label': deviceLabel.trim(),
      },
    );
    final data = expectSuccessJson(response, 'Login');

    if (_transport == SessionTransport.bearer) {
      final token = (data['token'] as String?)?.trim();
      if (token == null || token.isEmpty) {
        throw Exception(
          'Login failed: the server issued no token for a bearer session.',
        );
      }
      final origin = _originFor(response);
      final candidate = SessionCredential(token: token, origin: origin);
      try {
        await _store.write(candidate);
      } on SessionStoreException catch (error, stackTrace) {
        _credentialWarning =
            'Sign-in could not be completed because this device could not '
            'store the session: $error';
        try {
          await revokeIssuedBearerSession(candidate, settings: _settings);
        } on Exception catch (revokeError) {
          if (kDebugMode) {
            debugPrint(
              'AuthService._login: cleanup logout failed '
              '(${_describe(revokeError)})',
            );
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      _credential = candidate;
    }

    await persistLastSuccessfulUsername(username);
    if (generation != _generation) return;

    // The login response deliberately carries no user record; the probe is the
    // one place that shape is parsed, so there is only one contract to keep.
    await _probe(generation, startRecoveryOnFailure: true);
  }

  /// Sign out.
  ///
  /// Native logout is best-effort: deleting the keystore record genuinely ends
  /// the session on this device even with the server unreachable (the orphaned
  /// row stays visible in the sessions list and dies at idle expiry).
  ///
  /// Web logout is server-acknowledged: only the server can clear an HttpOnly
  /// cookie, so an unreachable server means logout did not happen, and saying
  /// otherwise would manufacture a signed-out state the browser will not honour.
  Future<void> logout() => _serialized(_logout);

  Future<void> _logout() async {
    _stopRecovery(resetAttempts: true);
    _generation++;
    final generation = _generation;
    _credentialWarning = null;
    final previousState = _state;
    _transitionTo(const AuthLoggingOut());

    Object? serverError;
    try {
      await apiPost(
        '/auth/logout/',
        settings: _settings,
        headers: jsonHeaders,
        body: const <String, dynamic>{},
      );
    } on Exception catch (error) {
      serverError = error;
    }

    if (generation != _generation) return;

    if (_transport == SessionTransport.cookie) {
      if (serverError != null) {
        if (_isClientRefusal(serverError)) {
          _transitionTo(previousState);
          throw LogoutRefusedException(
            'The server refused sign-out: ${_describe(serverError)}.',
          );
        }
        if (_isConfigError(serverError)) {
          _enterConfigError(_describe(serverError));
          return;
        }
        _enterUnavailable(
          'Could not sign out: ${_describe(serverError)}. The session is '
          'still active — recovery will verify it when the server is '
          'reachable.',
          startRecovery: true,
        );
        return;
      }
      _transitionTo(const AuthAnonymous());
      return;
    }

    await _forgetCredential();
    if (generation != _generation) return;
    if (serverError != null && kDebugMode) {
      debugPrint('AuthService._logout: server unreachable ($serverError)');
    }
    _transitionTo(const AuthAnonymous());
  }

  Future<void> _forgetCredential() async {
    if (_transport != SessionTransport.bearer) {
      return;
    }
    _credential = null;
    try {
      await _store.delete();
    } on SessionStoreException catch (error) {
      _credentialWarning =
          'Signed out here, but the stored session could not be removed from '
          'this device: $error';
    }
  }

  Future<void> _deleteLegacyCredentials() async {
    final store = _store;
    if (store is SecureSessionStore) {
      await store.deleteLegacyRecords();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _legacyPreferenceKeys) {
        await prefs.remove(key);
      }
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('AuthService._deleteLegacyCredentials: $error');
      }
    }
  }

  String _originFor(Response<dynamic> response) {
    final uri = response.requestOptions.uri;
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.port).origin;
  }

  @override
  void dispose() {
    _stopRecovery();
    super.dispose();
  }

  // ── unauthenticated flows ──────────────────────────────────

  Future<void> register(
    String username,
    String email,
    String password, {
    bool autoLogIn = true,
  }) async {
    final response = await apiPost(
      '/accounts/users/',
      settings: _settings,
      headers: jsonHeaders,
      body: {'username': username, 'email': email, 'password': password},
    );

    // Registration may return 200 or 201.
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Registration failed: (${response.statusCode}) ${response.data}',
      );
    }

    if (autoLogIn) {
      return login(username, password);
    }
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await apiPost(
      '/accounts/password/reset/',
      settings: _settings,
      headers: jsonHeaders,
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
      headers: jsonHeaders,
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'new_password': newPassword,
      },
    );
    expectSuccessJson(response, 'Password reset confirm');
  }

  static String _describe(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) {
        return 'server returned $status';
      }
      return error.message ?? 'the server could not be reached';
    }
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  static bool _isClientRefusal(Object error) {
    if (error is! DioException) {
      return false;
    }
    final status = error.response?.statusCode;
    return status != null && status >= 400 && status < 500;
  }

  /// Failures the api client raises before any request goes out, because the
  /// configuration itself is unusable. Permanent until settings change.
  static bool _isConfigError(Object error) =>
      error is UnsupportedOriginException ||
      error is MissingBackendUrlException;
}

class UserDataService extends ChangeNotifier {
  UserDataService(this._authService) {
    _authService.addListener(_handleAuthChange);
    _userData = _authService.userData;
  }

  UserData? _userData;
  final AuthService _authService;
  AppSettingsController? _settings;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  void _handleAuthChange() {
    // The auth probe already fetched this record; re-fetching on every auth
    // notification would double every login's round trips for nothing.
    _userData = _authService.userData;
    notifyListeners();
  }

  /// Re-read the user record, e.g. after the account screen changes it.
  Future<void> getUserInfo({bool notifyOnComplete = true}) async {
    if (!_authService.isAuthenticated) {
      _userData = null;
      if (notifyOnComplete) notifyListeners();
      return;
    }

    final generation = _authService.generation;
    try {
      final response = await apiGet(
        '/accounts/users/get_my_info/',
        settings: _settings,
        headers: jsonHeaders,
      );
      _userData = UserData.fromJson(
        expectSuccessJson(response, 'Fetch user info'),
      );
    } on Exception catch (error) {
      await _authService.reportPossibleSessionEnd(
        error,
        generation: generation,
      );
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
