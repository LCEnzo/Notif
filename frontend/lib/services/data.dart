import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';

const String _jsonContentType = 'application/json';
const String generalSelectorStrategy = 'GeneralSelectorStrategy';
const Duration _strategyCacheTtl = Duration(minutes: 2);

const List<String> defaultStrategyChoices = <String>[generalSelectorStrategy];

@immutable
class StrategyRecord {
  const StrategyRecord({
    required this.id,
    required this.className,
    required this.data,
  });

  factory StrategyRecord.fromJson(Map<String, dynamic> json) {
    return StrategyRecord(
      id: _asInt(json['id']) ?? 0,
      className: (json['strat_cls'] as String?)?.trim().isNotEmpty == true
          ? json['strat_cls'] as String
          : generalSelectorStrategy,
      data: Map<String, dynamic>.from((json['data'] as Map?) ?? const {}),
    );
  }

  final int id;
  final String className;
  final Map<String, dynamic> data;

  List<String> get selectors {
    final raw = data['selectors'];
    if (raw is! List) {
      return const [];
    }

    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}

@immutable
class Link {
  const Link({
    required this.id,
    required this.name,
    required this.url,
    this.lastScraped,
    required this.strategyId,
    required this.strategyClass,
    required this.selectors,
  });

  factory Link.fromJson(
    Map<String, dynamic> json,
    Map<int, StrategyRecord> strategies,
  ) {
    final strategyId = _asInt(json['strategy']);
    final strategy = strategyId != null ? strategies[strategyId] : null;

    return Link(
      id: _asInt(json['id']) ?? 0,
      name: (json['name'] as String?)?.trim() ?? '',
      url: (json['url'] as String?)?.trim() ?? '',
      lastScraped: _parseDateTime(json['last_scraped']),
      strategyId: strategyId,
      strategyClass: strategy?.className ?? 'UnknownStrategy',
      selectors: strategy?.selectors ?? const [],
    );
  }

  final int id;
  final String name;
  final String url;
  final DateTime? lastScraped;
  final int? strategyId;
  final String strategyClass;
  final List<String> selectors;

  String get strategyLabel => formatStrategyClassName(strategyClass);
}

enum NotificationStatus {
  unread,
  read,
  dismissed,
  unknown;

  static NotificationStatus fromWire(String? raw) {
    switch (raw) {
      case 'unread':
        return NotificationStatus.unread;
      case 'read':
        return NotificationStatus.read;
      case 'dismissed':
        return NotificationStatus.dismissed;
      default:
        return NotificationStatus.unknown;
    }
  }
}

@immutable
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.itemUrl,
    required this.status,
    required this.createdAt,
    this.readAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final update = Map<String, dynamic>.from(
      (json['update'] as Map?) ?? const {},
    );

    return NotificationItem(
      id: _asInt(json['id']) ?? 0,
      title: (update['title'] as String?)?.trim() ?? 'Untitled update',
      description: (update['description'] as String?)?.trim() ?? '',
      itemUrl: (update['item_url'] as String?)?.trim() ?? '',
      status: NotificationStatus.fromWire((json['status'] as String?)?.trim()),
      createdAt: _parseDateTime(update['created_at']) ?? DateTime.now(),
      readAt: _parseDateTime(json['read_at']),
    );
  }

  final int id;
  final String title;
  final String description;
  final String itemUrl;
  final NotificationStatus status;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => status == NotificationStatus.unread;

  NotificationItem copyWith({
    NotificationStatus? status,
    DateTime? readAt,
    bool clearReadAt = false,
  }) {
    return NotificationItem(
      id: id,
      title: title,
      description: description,
      itemUrl: itemUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
    );
  }
}

@immutable
class _StrategyResolution {
  const _StrategyResolution({required this.id, required this.created});

  final int id;
  final bool created;
}

enum LinkSort {
  newest('-pk,-pk', 'Newest'),
  oldest('pk,pk', 'Oldest'),
  recentlyScraped('-last_scraped,-pk', 'Recently scraped'),
  leastRecentlyScraped('last_scraped,pk', 'Least recently scraped');

  const LinkSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class LinkService extends ChangeNotifier {
  LinkService(this._authService);

  final AuthService _authService;
  AppSettingsController? _settings;

  List<Link> _links = const [];
  Map<int, StrategyRecord> _strategies = const {};
  List<String> _strategyChoices = defaultStrategyChoices;
  bool _strategyChoicesLoaded = false;
  DateTime? _strategiesFetchedAt;
  Future<Map<int, StrategyRecord>>? _strategiesLoad;
  Future<void>? _strategyChoicesLoad;
  int _linksFetchEpoch = 0;
  int _stateEpoch = 0;
  bool _loading = false;
  bool _creating = false;
  bool _scrapingAll = false;
  String? _error;

  // Pagination & ordering — plumbing only, no UI exposed yet.
  int _currentPage = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  LinkSort _ordering = LinkSort.newest;
  int _totalCount = 0;

  final Set<int> _scrapingIds = <int>{};
  final Set<int> _updatingIds = <int>{};
  final Set<int> _deletingIds = <int>{};

  void updateDependencies(
    AuthService authService,
    AppSettingsController? settings,
  ) {
    _settings = settings;

    if (authService.jwt == null) {
      _resetState();
    }
  }

  List<Link> get links => _links;
  List<String> get strategyChoices => _strategyChoices;
  bool get loading => _loading;
  bool get creating => _creating;
  bool get scrapingAll => _scrapingAll;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  LinkSort get ordering => _ordering;
  int get currentPage => _currentPage;
  int get totalCount => _totalCount;
  int get totalPages =>
      _totalCount == 0 ? 1 : (_totalCount / 100).ceil();
  String? get error => _error;

  bool isScrapingLink(int id) => _scrapingIds.contains(id);
  bool isUpdatingLink(int id) => _updatingIds.contains(id);
  bool isDeletingLink(int id) => _deletingIds.contains(id);

  Future<void> ensureStrategyChoicesLoaded() async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      return;
    }

    await _ensureStrategyChoicesLoaded(jwt, stateEpoch: _stateEpoch);
  }

  Future<void> fetchLinks() async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      _resetState();
      return;
    }

    final stateEpoch = _stateEpoch;
    final fetchEpoch = ++_linksFetchEpoch;
    _loading = true;
    _loadingMore = false;
    _error = null;
    notifyListeners();

    try {
      final strategies = await _ensureStrategiesLoaded(
        jwt,
        stateEpoch: stateEpoch,
      );
      await _ensureStrategyChoicesLoaded(jwt, stateEpoch: stateEpoch);

      final response = await apiGet(
        '/monitoring/links/?page=1&page_size=100&ordering=${_ordering.apiValue}',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      final body = expectSuccessJson(response, 'Fetch links');
      final results = (body['results'] as List?) ?? const [];
      final links = results
          .map(
            (item) => Link.fromJson(
              Map<String, dynamic>.from(item as Map),
              strategies,
            ),
          )
          .toList(growable: false);

      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _links = links;
      _currentPage = 1;
      _hasMore = body['next'] != null;
      _totalCount = (body['count'] as int?) ?? links.length;
    } catch (error) {
      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _error = describeDataError(error);
    } finally {
      if (_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Change sort order and re-fetch from page 1.
  Future<void> setOrdering(LinkSort value) async {
    if (_ordering == value) return;
    _ordering = value;
    await fetchLinks();
  }

  /// Fetch a specific page and replace the current list entirely.
  Future<void> goToPage(int page) async {
    final jwt = _authService.jwt;
    if (jwt == null || page < 1) return;

    final stateEpoch = _stateEpoch;
    final fetchEpoch = ++_linksFetchEpoch;
    _loading = true;
    _loadingMore = false;
    _error = null;
    notifyListeners();

    try {
      final strategies = await _ensureStrategiesLoaded(
        jwt,
        stateEpoch: stateEpoch,
      );
      final response = await apiGet(
        '/monitoring/links/?page=$page&page_size=100&ordering=${_ordering.apiValue}',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      final body = expectSuccessJson(response, 'Fetch links page $page');
      final results = (body['results'] as List?) ?? const [];
      final links = results
          .map(
            (item) => Link.fromJson(
              Map<String, dynamic>.from(item as Map),
              strategies,
            ),
          )
          .toList(growable: false);

      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _links = links;
      _currentPage = page;
      _hasMore = body['next'] != null;
      _totalCount = (body['count'] as int?) ?? links.length;
    } catch (error) {
      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _error = describeDataError(error);
    } finally {
      if (_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> createLink({
    required String name,
    required String url,
    required String strategyClass,
    required String selectorsText,
  }) async {
    final jwt = _authService.jwt;
    final userId = _authService.currentUserId;
    if (jwt == null || userId == null) {
      _error = 'You need to sign in again before creating a link.';
      notifyListeners();
      return false;
    }

    _creating = true;
    _error = null;
    notifyListeners();

    _StrategyResolution? strategyResolution;
    var linkCreated = false;

    try {
      strategyResolution = await _resolveStrategy(
        jwt: jwt,
        strategyClass: strategyClass,
        selectorsText: selectorsText,
      );

      final response = await apiPost(
        '/monitoring/links/',
        settings: _settings,
        headers: _authHeaders(jwt),
        body: {
          'name': name.trim(),
          'url': url.trim(),
          'user': userId,
          'strategy': strategyResolution.id,
        },
      );

      expectSuccessStatus(
        response,
        'Create link',
        successCodes: const {200, 201},
      );

      linkCreated = true;
      await fetchLinks();
      return true;
    } catch (error) {
      _error = describeDataError(error);
      if (!linkCreated && strategyResolution?.created == true) {
        await _deleteStrategyIfUnused(jwt, strategyResolution!.id);
      }
      return false;
    } finally {
      _creating = false;
      notifyListeners();
    }
  }

  Future<bool> updateLink({
    required Link link,
    required String name,
    required String url,
    required String strategyClass,
    required String selectorsText,
  }) async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      _error = 'You need to sign in again before updating a link.';
      notifyListeners();
      return false;
    }

    _updatingIds.add(link.id);
    _error = null;
    notifyListeners();

    _StrategyResolution? strategyResolution;
    var linkUpdated = false;

    try {
      var strategyId = link.strategyId;
      final selectorsChanged = strategyClass == generalSelectorStrategy
          ? !listEquals(normalizeSelectors(selectorsText), link.selectors)
          : false;

      if (strategyId == null ||
          strategyClass != link.strategyClass ||
          selectorsChanged) {
        strategyResolution = await _resolveStrategy(
          jwt: jwt,
          strategyClass: strategyClass,
          selectorsText: selectorsText,
        );
        strategyId = strategyResolution.id;
      }

      final response = await apiPatch(
        '/monitoring/links/${link.id}/',
        settings: _settings,
        headers: _authHeaders(jwt),
        body: {'name': name.trim(), 'url': url.trim(), 'strategy': strategyId},
      );

      expectSuccessStatus(response, 'Update link', successCodes: const {200});
      linkUpdated = true;

      if (link.strategyId != null && link.strategyId != strategyId) {
        await _deleteStrategyIfUnused(jwt, link.strategyId!);
      }

      await fetchLinks();
      return true;
    } catch (error) {
      _error = describeDataError(error);
      if (!linkUpdated && strategyResolution?.created == true) {
        await _deleteStrategyIfUnused(jwt, strategyResolution!.id);
      }
      return false;
    } finally {
      _updatingIds.remove(link.id);
      notifyListeners();
    }
  }

  Future<bool> deleteLink(Link link) async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      _error = 'You need to sign in again before deleting a link.';
      notifyListeners();
      return false;
    }

    _deletingIds.add(link.id);
    _error = null;
    notifyListeners();

    try {
      final response = await apiDelete(
        '/monitoring/links/${link.id}/',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      expectSuccessStatus(response, 'Delete link');
      _links = _links
          .where((item) => item.id != link.id)
          .toList(growable: false);
      if (link.strategyId != null) {
        await _deleteStrategyIfUnused(jwt, link.strategyId!);
      }
      return true;
    } catch (error) {
      _error = describeDataError(error);
      return false;
    } finally {
      _deletingIds.remove(link.id);
      notifyListeners();
    }
  }

  Future<String?> triggerScrape({int? linkId}) async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      _error = 'You need to sign in again before running a scrape.';
      notifyListeners();
      return null;
    }

    if (linkId == null) {
      _scrapingAll = true;
    } else {
      _scrapingIds.add(linkId);
    }
    _error = null;
    notifyListeners();

    try {
      final response = await apiPost(
        '/monitoring/trigger-scrape/',
        settings: _settings,
        headers: _authHeaders(jwt),
        body: linkId == null ? const <String, dynamic>{} : {'link_id': linkId},
      );

      final data = expectSuccessJson(response, 'Trigger scrape');
      await fetchLinks();
      return _formatScrapeResult(data, linkId: linkId);
    } catch (error) {
      _error = describeDataError(error);
      return null;
    } finally {
      _scrapingAll = false;
      if (linkId != null) {
        _scrapingIds.remove(linkId);
      }
      notifyListeners();
    }
  }

  Future<int> _createStrategy({
    required JWT jwt,
    required String strategyClass,
    required String selectorsText,
  }) async {
    final response = await apiPost(
      '/monitoring/strategies/',
      settings: _settings,
      headers: _authHeaders(jwt),
      body: {
        'strat_cls': strategyClass,
        'data': buildStrategyData(
          strategyClass: strategyClass,
          selectorsText: selectorsText,
        ),
      },
    );

    expectSuccessStatus(
      response,
      'Create strategy',
      successCodes: const {200, 201},
    );
    final json = Map<String, dynamic>.from(response.data as Map);
    final strategy = StrategyRecord.fromJson(json);
    _strategies = Map<int, StrategyRecord>.from(_strategies)
      ..[strategy.id] = strategy;
    _strategiesFetchedAt = DateTime.now();
    return strategy.id;
  }

  Future<_StrategyResolution> _resolveStrategy({
    required JWT jwt,
    required String strategyClass,
    required String selectorsText,
  }) async {
    await _ensureStrategiesLoaded(jwt, stateEpoch: _stateEpoch);

    final strategyData = buildStrategyData(
      strategyClass: strategyClass,
      selectorsText: selectorsText,
    );
    final existing = _findMatchingStrategy(
      strategyClass: strategyClass,
      strategyData: strategyData,
    );
    if (existing != null) {
      return _StrategyResolution(id: existing.id, created: false);
    }

    final id = await _createStrategy(
      jwt: jwt,
      strategyClass: strategyClass,
      selectorsText: selectorsText,
    );
    return _StrategyResolution(id: id, created: true);
  }

  StrategyRecord? _findMatchingStrategy({
    required String strategyClass,
    required Map<String, dynamic> strategyData,
  }) {
    for (final strategy in _strategies.values) {
      if (strategy.className != strategyClass) {
        continue;
      }

      if (strategyClass == generalSelectorStrategy) {
        final rawSelectors = strategyData['selectors'];
        final expectedSelectors = rawSelectors is List
            ? rawSelectors
                  .map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false)
            : const <String>[];
        if (listEquals(strategy.selectors, expectedSelectors)) {
          return strategy;
        }
        continue;
      }

      if (mapEquals(strategy.data, strategyData)) {
        return strategy;
      }
    }

    return null;
  }

  Future<void> _deleteStrategyIfUnused(
    JWT jwt,
    int strategyId,
  ) async {
    try {
      final response = await apiDelete(
        '/monitoring/strategies/$strategyId/',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      expectSuccessStatus(response, 'Delete strategy');
      _strategies = Map<int, StrategyRecord>.from(_strategies)
        ..remove(strategyId);
      _strategiesFetchedAt = DateTime.now();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('LinkService._deleteStrategyIfUnused($strategyId): $error');
      }
    }
  }

  Future<Map<int, StrategyRecord>> _ensureStrategiesLoaded(
    JWT jwt, {
    required int stateEpoch,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _hasFreshStrategies) {
      return _strategies;
    }

    final existingLoad = _strategiesLoad;
    if (existingLoad != null) {
      return existingLoad;
    }

    final load = _fetchStrategies(jwt, stateEpoch: stateEpoch);
    _strategiesLoad = load;

    try {
      return await load;
    } finally {
      if (identical(_strategiesLoad, load)) {
        _strategiesLoad = null;
      }
    }
  }

  Future<Map<int, StrategyRecord>> _fetchStrategies(
    JWT jwt, {
    required int stateEpoch,
  }) async {
    final response = await apiGet(
      '/monitoring/strategies/',
      settings: _settings,
      headers: _authHeaders(jwt),
    );

    final strategies = expectSuccessList(response, 'Fetch strategies')
        .map(
          (item) =>
              StrategyRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);

    final nextStrategies = <int, StrategyRecord>{
      for (final strategy in strategies) strategy.id: strategy,
    };
    if (!_isCurrentState(stateEpoch)) {
      return _strategies;
    }

    _strategies = nextStrategies;
    _strategiesFetchedAt = DateTime.now();
    return nextStrategies;
  }

  Future<void> _ensureStrategyChoicesLoaded(
    JWT jwt, {
    required int stateEpoch,
  }) async {
    if (_strategyChoicesLoaded) {
      return;
    }

    final existingLoad = _strategyChoicesLoad;
    if (existingLoad != null) {
      return existingLoad;
    }

    final load = _fetchStrategyChoices(jwt, stateEpoch: stateEpoch);
    _strategyChoicesLoad = load;

    try {
      await load;
    } finally {
      if (identical(_strategyChoicesLoad, load)) {
        _strategyChoicesLoad = null;
      }
    }
  }

  Future<void> _fetchStrategyChoices(
    JWT jwt, {
    required int stateEpoch,
  }) async {
    try {
      final response = await apiGet(
        '/monitoring/strat-choices',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      final choices = expectSuccessList(response, 'Fetch strategy choices')
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

      if (!_isCurrentState(stateEpoch)) {
        return;
      }
      _strategyChoices = choices.isEmpty
          ? defaultStrategyChoices
          : List<String>.from(choices);
      _strategyChoicesLoaded = true;
    } catch (error) {
      if (!_isCurrentState(stateEpoch)) {
        return;
      }
      if (kDebugMode) {
        debugPrint('LinkService._fetchStrategyChoices: $error');
      }
      _strategyChoices = defaultStrategyChoices;
      _strategyChoicesLoaded = false;
    }
  }

  bool get _hasFreshStrategies {
    final fetchedAt = _strategiesFetchedAt;
    if (fetchedAt == null || _strategies.isEmpty) {
      return false;
    }

    return DateTime.now().difference(fetchedAt) < _strategyCacheTtl;
  }

  bool _isCurrentState(int stateEpoch) => _stateEpoch == stateEpoch;

  bool _isCurrentLinksFetch(int fetchEpoch, int stateEpoch) =>
      _linksFetchEpoch == fetchEpoch && _isCurrentState(stateEpoch);

  void _resetState() {
    if (_links.isEmpty &&
        _strategies.isEmpty &&
        listEquals(_strategyChoices, defaultStrategyChoices) &&
        !_strategyChoicesLoaded &&
        _strategiesFetchedAt == null &&
        _strategiesLoad == null &&
        _strategyChoicesLoad == null &&
        _error == null &&
        !_loading &&
        !_loadingMore &&
        !_hasMore &&
        _currentPage == 0 &&
        _totalCount == 0 &&
        _ordering == LinkSort.newest &&
        !_creating &&
        !_scrapingAll &&
        _scrapingIds.isEmpty &&
        _updatingIds.isEmpty &&
        _deletingIds.isEmpty) {
      return;
    }

    _stateEpoch += 1;
    _linksFetchEpoch += 1;
    _links = const [];
    _strategies = const {};
    _strategyChoices = defaultStrategyChoices;
    _strategyChoicesLoaded = false;
    _strategiesFetchedAt = null;
    _strategiesLoad = null;
    _strategyChoicesLoad = null;
    _loading = false;
    _loadingMore = false;
    _hasMore = false;
    _currentPage = 0;
    _totalCount = 0;
    _ordering = LinkSort.newest;
    _creating = false;
    _scrapingAll = false;
    _error = null;
    _scrapingIds.clear();
    _updatingIds.clear();
    _deletingIds.clear();
    notifyListeners();
  }
}

enum NotifSort {
  newest('-update__created_at,-pk', 'Newest'),
  oldest('update__created_at,pk', 'Oldest');

  const NotifSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class NotificationService extends ChangeNotifier {
  NotificationService(this._authService);

  static const int _pageSize = 50;

  final AuthService _authService;
  AppSettingsController? _settings;

  List<NotificationItem> _notifications = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _markingAllRead = false;
  int _fetchEpoch = 0;
  int _currentPage = 0;
  bool _hasMore = false;
  // Server-reported global unread count. Local count over `_notifications`
  // would be wrong under pagination — unread items can sit on later pages.
  int _totalUnreadCount = 0;
  NotifSort _ordering = NotifSort.newest;
  int _totalCount = 0;
  String? _error;

  final Set<int> _markingReadIds = <int>{};

  void updateDependencies(
    AuthService authService,
    AppSettingsController? settings,
  ) {
    _settings = settings;

    if (authService.jwt == null) {
      _resetState();
    }
  }

  List<NotificationItem> get notifications => _notifications;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  bool get markingAllRead => _markingAllRead;
  NotifSort get ordering => _ordering;
  int get currentPage => _currentPage;
  int get totalCount => _totalCount;
  int get totalPages =>
      _totalCount == 0 ? 1 : (_totalCount / _pageSize).ceil();
  String? get error => _error;
  int get unreadCount => _totalUnreadCount;

  bool isMarkingRead(int id) => _markingReadIds.contains(id);

  Future<void> fetchNotifications() async {
    final jwt = _authService.jwt;
    if (jwt == null) {
      _resetState();
      return;
    }

    final fetchEpoch = ++_fetchEpoch;
    _loading = true;
    // A refresh racing with an in-flight loadMore would otherwise leave
    // _loadingMore = true forever, since the stale loadMore's epoch check
    // exits without clearing it.
    _loadingMore = false;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGet(
        '/monitoring/notifications/?page=1&page_size=$_pageSize&ordering=${_ordering.apiValue}',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      final body = expectSuccessJson(response, 'Fetch notifications');
      final results = (body['results'] as List?) ?? const [];
      final notifications =
          results
              .map(
                (item) => NotificationItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)
            ..sort(_compareNotifications);

      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _notifications = notifications;
      _currentPage = 1;
      _hasMore = body['next'] != null;
      _totalCount = (body['count'] as int?) ?? 0;
      _totalUnreadCount = (body['unread_count'] as int?) ?? 0;
    } catch (error) {
      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _error = describeDataError(error);
    } finally {
      if (_fetchEpoch == fetchEpoch) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Change sort order and re-fetch from page 1.
  Future<void> setOrdering(NotifSort value) async {
    if (_ordering == value) return;
    _ordering = value;
    await fetchNotifications();
  }

  /// Fetch a specific page and replace the current list entirely.
  Future<void> goToPage(int page) async {
    final jwt = _authService.jwt;
    if (jwt == null || page < 1) return;

    final fetchEpoch = ++_fetchEpoch;
    _loadingMore = false;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiGet(
        '/monitoring/notifications/?page=$page&page_size=$_pageSize&ordering=${_ordering.apiValue}',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      final body = expectSuccessJson(response, 'Fetch notifications page $page');
      final results = (body['results'] as List?) ?? const [];
      final notifications =
          results
              .map(
                (item) => NotificationItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)
            ..sort(_compareNotifications);

      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _notifications = notifications;
      _currentPage = page;
      _hasMore = body['next'] != null;
      _totalCount = (body['count'] as int?) ?? 0;
      _totalUnreadCount = (body['unread_count'] as int?) ?? _totalUnreadCount;
    } catch (error) {
      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _error = describeDataError(error);
    } finally {
      if (_fetchEpoch == fetchEpoch) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> toggleRead(int id) async {
    final jwt = _authService.jwt;
    final notification = _notifications.cast<NotificationItem?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (jwt == null || notification == null) {
      return false;
    }
    // Only read↔unread is a valid flip. Dismissed and unknown states should
    // not be resurrected to unread by a chip tap.
    if (notification.status != NotificationStatus.unread &&
        notification.status != NotificationStatus.read) {
      return false;
    }

    final wasUnread = notification.isUnread;
    final targetStatus = wasUnread
        ? NotificationStatus.read
        : NotificationStatus.unread;
    final wireStatus = wasUnread ? 'read' : 'unread';

    _markingReadIds.add(id);
    _error = null;
    notifyListeners();

    try {
      final response = await apiPatch(
        '/monitoring/notifications/$id/',
        settings: _settings,
        headers: _authHeaders(jwt),
        body: {'status': wireStatus},
      );

      expectSuccessStatus(response, 'Toggle notification read state');

      _notifications =
          _notifications
              .map(
                (item) => item.id == id
                    ? item.copyWith(
                        status: targetStatus,
                        readAt: wasUnread ? DateTime.now() : null,
                        clearReadAt: !wasUnread,
                      )
                    : item,
              )
              .toList(growable: false)
            ..sort(_compareNotifications);
      // Mirror the server-side change locally; the count stays accurate
      // until the next fetch refreshes it from the envelope.
      _totalUnreadCount = (_totalUnreadCount + (wasUnread ? -1 : 1))
          .clamp(0, 1 << 30);
      return true;
    } catch (error) {
      _error = describeDataError(error);
      return false;
    } finally {
      _markingReadIds.remove(id);
      notifyListeners();
    }
  }

  Future<bool> markRead(int id) async {
    final notification = _notifications.cast<NotificationItem?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (notification == null || !notification.isUnread) {
      return false;
    }
    return toggleRead(id);
  }

  Future<void> markAllRead() async {
    final jwt = _authService.jwt;
    if (jwt == null || unreadCount == 0) {
      return;
    }

    _markingAllRead = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiPost(
        '/monitoring/notifications/mark_all_read/',
        settings: _settings,
        headers: _authHeaders(jwt),
        body: const <String, dynamic>{},
      );

      expectSuccessStatus(response, 'Mark all notifications as read');
      final now = DateTime.now();
      _notifications =
          _notifications
              .map(
                (item) => item.copyWith(
                  status: NotificationStatus.read,
                  readAt: now,
                ),
              )
              .toList(growable: false)
            ..sort(_compareNotifications);
      // Server clears all unread for the user, including pages we haven't
      // loaded; reflect that locally rather than counting visible items.
      _totalUnreadCount = 0;
    } catch (error) {
      _error = describeDataError(error);
    } finally {
      _markingAllRead = false;
      notifyListeners();
    }
  }

  void _resetState() {
    if (_notifications.isEmpty &&
        _error == null &&
        !_loading &&
        !_loadingMore &&
        !_markingAllRead &&
        _currentPage == 0 &&
        !_hasMore &&
        _totalCount == 0 &&
        _totalUnreadCount == 0 &&
        _ordering == NotifSort.newest) {
      return;
    }

    _fetchEpoch += 1;
    _notifications = const [];
    _loading = false;
    _loadingMore = false;
    _markingAllRead = false;
    _currentPage = 0;
    _hasMore = false;
    _totalCount = 0;
    _totalUnreadCount = 0;
    _ordering = NotifSort.newest;
    _error = null;
    _markingReadIds.clear();
    notifyListeners();
  }
}

Map<String, dynamic> buildStrategyData({
  required String strategyClass,
  required String selectorsText,
}) {
  if (strategyClass == generalSelectorStrategy) {
    return <String, dynamic>{'selectors': normalizeSelectors(selectorsText)};
  }

  return <String, dynamic>{};
}

List<String> normalizeSelectors(String selectorsText) {
  final selectors = selectorsText
      .split('\n')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  if (selectors.isEmpty) {
    return const ['body'];
  }

  return selectors;
}

String formatStrategyClassName(String raw) {
  switch (raw) {
    case 'SBSVThreadmarksStrategy':
      return 'SB/SV Threadmarks';
    case 'QQAlertsStrategy':
      return 'QQ Alerts';
    case 'KemonoFavouritesStrategy':
      return 'Kemono Favourites';
    default:
      final withoutSuffix = raw.replaceAll(RegExp(r'Strategy$'), '');
      return withoutSuffix
          .replaceAllMapped(
            RegExp(r'([a-z0-9])([A-Z])'),
            (match) => '${match.group(1)} ${match.group(2)}',
          )
          .trim();
  }
}

String describeDataError(Object error) {
  if (error is DioException) {
    final response = error.response;
    final extracted = _extractErrorMessage(response?.data);
    if (extracted != null && extracted.isNotEmpty) {
      return extracted;
    }

    if (response?.statusCode != null) {
      return 'Request failed with status ${response!.statusCode}.';
    }

    return error.message ?? 'The request could not be completed.';
  }

  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

Map<String, String> _authHeaders(JWT jwt) {
  return <String, String>{
    'Authorization': 'Bearer ${jwt.access}',
    'Content-Type': _jsonContentType,
  };
}

DateTime? _parseDateTime(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

int _compareNotifications(NotificationItem left, NotificationItem right) {
  if (left.isUnread != right.isUnread) {
    return left.isUnread ? -1 : 1;
  }
  return right.createdAt.compareTo(left.createdAt);
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _extractErrorMessage(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is List) {
    final parts = value
        .map(_extractErrorMessage)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('\n');
  }

  if (value is Map) {
    final detail = value['detail'] ?? value['message'] ?? value['error'];
    final direct = _extractErrorMessage(detail);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final parts = <String>[];
    for (final entry in value.entries) {
      final message = _extractErrorMessage(entry.value);
      if (message != null && message.isNotEmpty) {
        parts.add('${entry.key}: $message');
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('\n');
  }

  return null;
}

String _formatScrapeResult(Map<String, dynamic> data, {required int? linkId}) {
  if (linkId != null) {
    final status = data['status'] as String?;
    if (status == 'ok') {
      final updatesFound = _asInt(data['updates_found']) ?? 0;
      return updatesFound == 0
          ? 'Scrape finished. No new updates were found.'
          : 'Scrape finished. Found $updatesFound new '
                '${updatesFound == 1 ? 'update' : 'updates'}.';
    }
    return _extractErrorMessage(data) ?? 'Scrape failed.';
  }

  var okCount = 0;
  var totalUpdates = 0;
  var failedCount = 0;

  for (final value in data.values) {
    if (value is! Map) {
      continue;
    }
    final status = value['status'] as String?;
    if (status == 'ok') {
      okCount += 1;
      totalUpdates += _asInt(value['count']) ?? 0;
    } else {
      failedCount += 1;
    }
  }

  if (okCount == 0 && failedCount == 0) {
    return 'Scrape finished, but the server returned no summary.';
  }

  final updatesText = totalUpdates == 1 ? '1 update' : '$totalUpdates updates';
  if (failedCount == 0) {
    return 'Scraped $okCount ${okCount == 1 ? 'link' : 'links'} and found '
        '$updatesText.';
  }

  return 'Scraped $okCount ${okCount == 1 ? 'link' : 'links'}, found '
      '$updatesText, and $failedCount '
      '${failedCount == 1 ? 'link failed' : 'links failed'}.';
}