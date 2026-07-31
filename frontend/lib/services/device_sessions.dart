import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';

/// One live session — one signed-in device — as the server sees it.
@immutable
class DeviceSession {
  const DeviceSession({
    required this.publicId,
    required this.deviceLabel,
    required this.transport,
    required this.createdAt,
    required this.lastUsedAt,
    required this.ip,
    required this.userAgent,
    required this.isCurrent,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
    publicId: json['public_id'] as String? ?? '',
    deviceLabel: (json['device_label'] as String?)?.trim() ?? '',
    transport: json['transport'] as String? ?? '',
    createdAt: DateTime.tryParse(
      json['created_at'] as String? ?? '',
    )?.toLocal(),
    lastUsedAt: DateTime.tryParse(
      json['last_used_at'] as String? ?? '',
    )?.toLocal(),
    ip: json['ip'] as String? ?? '',
    userAgent: (json['user_agent'] as String?)?.trim() ?? '',
    isCurrent: json['current'] == true,
  );

  final String publicId;
  final String deviceLabel;
  final String transport;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final String ip;
  final String userAgent;
  final bool isCurrent;

  String get displayName {
    if (deviceLabel.isNotEmpty) return deviceLabel;
    return transport == 'cookie' ? 'Browser session' : 'Native session';
  }
}

/// The devices screen's data.
///
/// This list is the whole answer to "I signed in somewhere I should not have",
/// and the reason the design can accept last-server-committed-wins for
/// concurrent logins and logouts: whatever survives a race is visible here and
/// revocable in one tap.
class DeviceSessionService extends ChangeNotifier {
  DeviceSessionService(this._authService);

  AuthService _authService;
  AppSettingsController? _settings;

  List<DeviceSession> _sessions = const [];
  bool _loading = false;
  String? _error;
  final Set<String> _revoking = <String>{};

  List<DeviceSession> get sessions => _sessions;
  bool get loading => _loading;
  String? get error => _error;
  bool isRevoking(String publicId) => _revoking.contains(publicId);

  void updateDependencies(
    AuthService authService,
    AppSettingsController? settings,
  ) {
    _authService = authService;
    _settings = settings;
    if (!authService.isAuthenticated) {
      _sessions = const [];
    }
  }

  Future<void> fetch() async {
    if (!_authService.isAuthenticated) {
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGet(
        '/auth/sessions/',
        settings: _settings,
        headers: jsonHeaders,
      );
      // The per-user session cap bounds this list, so there is no pagination
      // envelope to unwrap and none to add later.
      _sessions = expectSuccessList(response, 'Fetch sessions')
          .map(
            (item) =>
                DeviceSession.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
    } on Exception catch (error) {
      _error = 'Could not load your devices: $error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Revoke one session. Revoking your own signs this device out on its next
  /// request; the caller decides whether to make that immediate.
  Future<bool> revoke(String publicId) async {
    if (!_authService.isAuthenticated || _revoking.contains(publicId)) {
      return false;
    }

    _revoking.add(publicId);
    _error = null;
    notifyListeners();

    try {
      final response = await apiDelete(
        '/auth/sessions/$publicId/',
        settings: _settings,
        headers: jsonHeaders,
      );
      expectSuccessJson(response, 'Revoke session');
      await fetch();
      return true;
    } on Exception catch (error) {
      _error = 'Could not revoke that device: $error';
      return false;
    } finally {
      _revoking.remove(publicId);
      notifyListeners();
    }
  }

  /// Revoke every session except this one.
  Future<bool> revokeAllOthers() async {
    if (!_authService.isAuthenticated) {
      return false;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiPost(
        '/auth/sessions/revoke_all/',
        settings: _settings,
        headers: jsonHeaders,
        body: const <String, dynamic>{},
      );
      expectSuccessJson(response, 'Revoke other sessions');
      await fetch();
      return true;
    } on Exception catch (error) {
      _error = 'Could not revoke your other devices: $error';
      _loading = false;
      notifyListeners();
      return false;
    }
  }
}
