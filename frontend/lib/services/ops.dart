import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notif/commons/download_helper.dart';
import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/client_events.dart';

class SystemEvent {
  const SystemEvent({
    required this.id,
    required this.createdAt,
    required this.level,
    required this.source,
    required this.kind,
    required this.message,
    required this.details,
  });

  factory SystemEvent.fromJson(Map<String, dynamic> json) {
    // Parse through the schema-generated type first (see data.dart). The
    // generator makes readOnly fields nullable, so `required` is checked here.
    final parsed = parseContract(
      'SystemEvent',
      () => api.SystemEvent.fromJson(json),
    );
    // The generated enum maps unknown levels to null; keep the wire string so
    // a level added server-side still renders.
    final level = json['level'];
    final details = parsed.details;
    return SystemEvent(
      id: _required(parsed.id, 'id'),
      createdAt: _required(parsed.createdAt, 'created_at').toLocal(),
      level: _required(level is String ? level : null, 'level'),
      source: _required(parsed.source, 'source'),
      kind: _required(parsed.kind, 'kind'),
      message: _required(parsed.message, 'message'),
      details: details is Map ? Map<String, dynamic>.from(details) : const {},
    );
  }
  final int id;
  final DateTime createdAt;
  final String level;
  final String source;
  final String kind;
  final String message;
  final Map<String, dynamic> details;
}

T _required<T extends Object>(T? value, String field) =>
    value ??
    (throw ContractViolation(
      schema: 'SystemEvent',
      detail: '$field is missing or mistyped',
    ));

class CaddyLogEntry {
  const CaddyLogEntry({required this.data});
  final Map<String, dynamic> data;

  String get method {
    final request = data['request'];
    if (request is Map && request['method'] is String) {
      return request['method'] as String;
    }
    return '';
  }

  String get uri {
    final request = data['request'];
    if (request is Map && request['uri'] is String) {
      return request['uri'] as String;
    }
    return data['uri']?.toString() ?? '';
  }

  String get status => data['status']?.toString() ?? '';
  String get remoteIp {
    final request = data['request'];
    if (request is Map && request['remote_ip'] is String) {
      return request['remote_ip'] as String;
    }
    return '';
  }
}

class OpsException implements Exception {
  const OpsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpsService extends ChangeNotifier {
  OpsService(this._authService);

  AuthService _authService;
  AppSettingsController? _settings;
  final List<SystemEvent> _events = [];
  final List<CaddyLogEntry> _caddyLogs = [];
  bool _loading = false;
  bool _caddyLogsLoading = false;
  bool _downloading = false;
  String? _error;

  void updateDependencies(
    AuthService authService,
    AppSettingsController? settings,
  ) {
    _authService = authService;
    _settings = settings;
  }

  /// The api_client attaches the credential itself; this only asserts that
  /// there is one to attach, so an ops screen opened while signed out fails
  /// with a sentence instead of a 401.
  Map<String, String> _authHeaders() {
    if (!_authService.isAuthenticated) {
      throw const OpsException(
        'You need to sign in before viewing operations data.',
      );
    }
    return const {'Content-Type': 'application/json'};
  }

  Future<void> fetchEvents() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGet(
        '/ops/events/?page_size=50',
        settings: _settings,
        headers: _authHeaders(),
      );
      final data = expectSuccessJson(response, 'Fetch system events');
      final rawResults = data['results'];
      if (rawResults is! List) {
        throw Exception('Fetch system events failed: missing results list.');
      }
      // Parse everything before swapping, so a bad event keeps the last
      // complete list instead of leaving a partial one.
      final events = rawResults
          .map(
            (item) => item is Map<String, dynamic>
                ? SystemEvent.fromJson(item)
                : throw ContractViolation(
                    schema: 'SystemEvent',
                    detail: 'event is ${item.runtimeType}, not an object',
                  ),
          )
          .toList(growable: false);
      _events
        ..clear()
        ..addAll(events);
    } on Exception catch (error) {
      _recordFailure(error, endpoint: 'GET /ops/events/');
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCaddyLogs() async {
    _caddyLogsLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGet(
        '/ops/logs/caddy/?limit=50',
        settings: _settings,
        headers: _authHeaders(),
      );
      final data = expectSuccessJson(response, 'Fetch Caddy logs');
      final rawResults = data['results'];
      if (rawResults is! List) {
        throw Exception('Fetch Caddy logs failed: missing results list.');
      }
      _caddyLogs
        ..clear()
        ..addAll(
          rawResults.whereType<Map<String, dynamic>>().map(
            (item) => CaddyLogEntry(data: Map<String, dynamic>.from(item)),
          ),
        );
    } on Exception catch (error) {
      _recordFailure(error, endpoint: 'GET /ops/logs/caddy/');
      _error = error.toString();
    } finally {
      _caddyLogsLoading = false;
      notifyListeners();
    }
  }

  Future<void> downloadSqliteBackup() async {
    _downloading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGetBytes(
        '/ops/backup/sqlite/',
        settings: _settings,
        headers: _authHeaders(),
      );
      expectSuccessStatus(response, 'Download SQLite backup');
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Download SQLite backup failed: empty response.');
      }
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '-');
      saveBytesAsFile(
        bytes: bytes,
        filename: 'notif-db-$timestamp.sqlite3',
        mimeType: 'application/vnd.sqlite3',
      );
    } on Exception catch (error) {
      _recordFailure(error, endpoint: 'GET /ops/backup/sqlite/');
      _error = error.toString();
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  List<SystemEvent> get events => List.unmodifiable(_events);
  List<CaddyLogEntry> get caddyLogs => List.unmodifiable(_caddyLogs);
  bool get loading => _loading;
  bool get caddyLogsLoading => _caddyLogsLoading;
  bool get downloading => _downloading;
  String? get error => _error;

  void _recordFailure(Object error, {required String endpoint}) {
    unawaited(
      reportClientFailure(
        settings: _settings,
        error: error,
        endpoint: endpoint,
      ),
    );
  }
}
