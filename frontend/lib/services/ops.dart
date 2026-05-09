import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notif/commons/download_helper.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/client_events.dart';
import 'package:notif/services/json_contracts.dart';

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

  factory SystemEvent.fromJson(JsonCursor json) {
    return SystemEvent(
      id: json.field('id').integer(),
      createdAt: json.field('created_at').dateTime(),
      level: json.field('level').string(allowEmpty: false),
      source: json.field('source').string(allowEmpty: false),
      kind: json.field('kind').string(allowEmpty: false),
      message: json.field('message').string(),
      details: json.optionalField('details')?.object() ?? const {},
    );
  }
  final int id;
  final DateTime createdAt;
  final String level;
  final String source;
  final String kind;
  final String message;
  final Map<String, Object?> details;
}

class CaddyLogEntry {
  const CaddyLogEntry({required this.data});
  final Map<String, Object?> data;

  String get method {
    final request = data['request'];
    if (request is Map<Object?, Object?>) {
      final method = request['method'];
      if (method is String) {
        return method.trim();
      }
    }
    return '';
  }

  String get uri {
    final request = data['request'];
    if (request is Map<Object?, Object?>) {
      final uri = request['uri'];
      if (uri is String) {
        return uri.trim();
      }
    }
    return data['uri']?.toString() ?? '';
  }

  String get status => data['status']?.toString() ?? '';
  String get remoteIp {
    final request = data['request'];
    if (request is Map<Object?, Object?>) {
      final remoteIp = request['remote_ip'];
      if (remoteIp is String) {
        return remoteIp.trim();
      }
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

  Map<String, String> _authHeaders() {
    final jwt = _authService.jwt;
    if (jwt == null) {
      throw const OpsException(
        'You need to sign in before viewing operations data.',
      );
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${jwt.access}',
    };
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
      final data = expectSuccessObject(response, 'Fetch system events');
      _events
        ..clear()
        ..addAll(data.field('results').items().map(SystemEvent.fromJson));
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
      final data = expectSuccessObject(response, 'Fetch Caddy logs');
      _caddyLogs
        ..clear()
        ..addAll(
          data
              .field('results')
              .items()
              .map((item) => CaddyLogEntry(data: item.object())),
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
