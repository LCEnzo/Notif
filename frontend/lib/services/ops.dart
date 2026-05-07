import 'package:flutter/foundation.dart';
import 'package:notif/commons/download_helper.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';

class SystemEvent {
  final int id;
  final DateTime createdAt;
  final String level;
  final String source;
  final String kind;
  final String message;
  final Map<String, dynamic> details;

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
    return SystemEvent(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      level: json['level'] as String,
      source: json['source'] as String,
      kind: json['kind'] as String,
      message: json['message'] as String,
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : const {},
    );
  }
}

class CaddyLogEntry {
  final Map<String, dynamic> data;

  const CaddyLogEntry({required this.data});

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
      throw StateError('You need to sign in before viewing operations data.');
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
      final data = expectSuccessJson(response, 'Fetch system events');
      final rawResults = data['results'];
      if (rawResults is! List) {
        throw Exception('Fetch system events failed: missing results list.');
      }
      _events
        ..clear()
        ..addAll(
          rawResults.whereType<Map<String, dynamic>>().map(
            (item) => SystemEvent.fromJson(Map<String, dynamic>.from(item)),
          ),
        );
    } catch (error) {
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
    } catch (error) {
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
    } catch (error) {
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
}
