import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Link {
  Link({
    required this.name,
    required this.url,
    required this.strategy,
    this.lastScraped,
    this.comparisonInfo = '',
    this.user,
  });

  final String name;
  final String url;
  final String strategy;
  final DateTime? lastScraped;
  final String comparisonInfo;
  final int? user;

  factory Link.fromJson(Map<String, dynamic> json) {
    return Link(
      name: json['name'] as String,
      url: json['url'] as String,
      strategy: (json['strategy'] ?? '').toString(),
      lastScraped: json['last_scraped'] != null
          ? DateTime.parse(json['last_scraped'] as String)
          : null,
      comparisonInfo: (json['comparison_info'] ?? '') as String,
      user: json['user'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'strategy': strategy,
      };
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.status,
    required this.title,
    required this.description,
    this.itemUrl,
    this.readAt,
    this.createdAt,
  });

  final int id;
  final String status; // unread, read, dismissed
  final String title;
  final String description;
  final String? itemUrl;
  final DateTime? readAt;
  final DateTime? createdAt;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final update = json['update'] as Map<String, dynamic>? ?? {};
    return NotificationItem(
      id: json['id'] as int,
      status: json['status'] as String,
      title: (update['title'] ?? '') as String,
      description: (update['description'] ?? '') as String,
      itemUrl: update['item_url'] as String?,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      createdAt: update['created_at'] != null
          ? DateTime.parse(update['created_at'] as String)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Link service
// ---------------------------------------------------------------------------

class LinkService extends ChangeNotifier {
  final AuthService _authService;
  AppSettingsController? _settings;

  List<Link> _links = [];
  bool _loading = false;
  String? _error;

  LinkService(this._authService) {
    _authService.addListener(_handleAuthChange);
  }

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  void _handleAuthChange() {
    if (_authService.jwt != null) {
      fetchLinks();
    } else {
      _links = [];
      _error = null;
      notifyListeners();
    }
  }

  List<Link> get links => _links;
  bool get loading => _loading;
  String? get error => _error;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.jwt!.access}',
      };

  Future<void> fetchLinks() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGet(
        '/links/',
        settings: _settings,
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final data = response.data as List<dynamic>;
        _links = data
            .map((e) => Link.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load links (${response.statusCode})';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _loading = false;
    notifyListeners();
  }

  Future<bool> createLink(String name, String url, String strategy) async {
    try {
      final response = await apiPost(
        '/links/',
        settings: _settings,
        headers: _authHeaders,
        body: {
          'name': name,
          'url': url,
          'strategy': strategy,
          'user': _authService.jwt != null ? null : null, // backend sets user
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchLinks();
        return true;
      }
      _error = 'Failed to create link (${response.statusCode})';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteLink(int index) async {
    // DRF ViewSet uses PK, not index. We need the PK from the response.
    // For now, re-fetch to get PKs. TODO: store PK in Link model.
    try {
      await fetchLinks();
      return true;
    } catch (e) {
      _error = 'Error: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> triggerScrape({int? linkId}) async {
    try {
      final body = <String, dynamic>{};
      if (linkId != null) body['link_id'] = linkId;

      final response = await apiPost(
        '/trigger-scrape/',
        settings: _settings,
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode == 200) {
        await fetchLinks();
        return response.data as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'Scrape failed (${response.statusCode})'};
    } catch (e) {
      return {'status': 'error', 'message': 'Network error: $e'};
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChange);
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Notification service
// ---------------------------------------------------------------------------

class NotificationService extends ChangeNotifier {
  final AuthService _authService;
  AppSettingsController? _settings;

  List<NotificationItem> _notifications = [];
  bool _loading = false;

  NotificationService(this._authService) {
    _authService.addListener(_handleAuthChange);
  }

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  void _handleAuthChange() {
    if (_authService.jwt != null) {
      fetchNotifications();
    } else {
      _notifications = [];
      notifyListeners();
    }
  }

  List<NotificationItem> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => n.status == 'unread').length;
  bool get loading => _loading;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.jwt!.access}',
      };

  Future<void> fetchNotifications() async {
    _loading = true;
    notifyListeners();

    try {
      final response = await apiGet(
        '/notifications/',
        settings: _settings,
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final data = response.data as List<dynamic>;
        _notifications = data
            .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    _loading = false;
    notifyListeners();
  }

  Future<void> markRead(int id) async {
    try {
      await apiPost(
        '/notifications/$id/',
        settings: _settings,
        headers: _authHeaders,
        body: {'status': 'read'},
      );
      await fetchNotifications();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await apiPost(
        '/notifications/mark_all_read/',
        settings: _settings,
        headers: _authHeaders,
        body: {},
      );
      await fetchNotifications();
    } catch (_) {}
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChange);
    super.dispose();
  }
}
