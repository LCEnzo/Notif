import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/client_events.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/json_contracts.dart';

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

  factory StrategyRecord.fromJson(JsonCursor json) {
    return StrategyRecord(
      id: json.field('id').integer(),
      className:
          json.optionalField('strat_cls')?.string(allowEmpty: false) ??
          generalSelectorStrategy,
      data: json.optionalField('data')?.object() ?? const {},
    );
  }

  final int id;
  final String className;
  final Map<String, Object?> data;

  List<String> get selectors {
    final raw = data['selectors'];
    if (raw is! List<Object?>) {
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
    JsonCursor json,
    Map<int, StrategyRecord> strategies,
  ) {
    final strategyId = json.optionalField('strategy')?.nullableInteger();
    final strategy = strategyId != null ? strategies[strategyId] : null;

    return Link(
      id: json.field('id').integer(),
      name: json.field('name').string(),
      url: json.field('url').string(),
      lastScraped: json.optionalField('last_scraped')?.nullableDateTime(),
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
  unknown
  ;

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

  factory NotificationItem.fromJson(JsonCursor json) {
    final update = json.field('update');
    return NotificationItem(
      id: json.field('id').integer(),
      title: update.field('title').string(allowEmpty: false),
      description: update.field('description').string(),
      itemUrl: update.field('item_url').string(),
      status: NotificationStatus.fromWire(
        json.field('status').string(allowEmpty: false),
      ),
      createdAt: update.field('created_at').dateTime(),
      readAt: json.optionalField('read_at')?.nullableDateTime(),
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
  newest('-pk', 'Newest'),
  oldest('pk', 'Oldest'),
  recentlyScraped('-last_scraped,-pk', 'Recently scraped'),
  leastRecentlyScraped('last_scraped,pk', 'Least recently scraped')
  ;

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
  int get totalPages => _totalCount == 0 ? 1 : (_totalCount / 100).ceil();
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

      final body = expectSuccessObject(response, 'Fetch links');
      final links = body
          .field('results')
          .items()
          .map((item) => Link.fromJson(item, strategies))
          .toList(growable: false);

      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _links = links;
      _currentPage = 1;
      _hasMore = body.hasNonNullField('next');
      _totalCount = body.field('count').integer();
    } on Exception catch (error) {
      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _recordFailure(error, endpoint: 'GET /monitoring/links/');
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

      final body = expectSuccessObject(response, 'Fetch links page $page');
      final links = body
          .field('results')
          .items()
          .map((item) => Link.fromJson(item, strategies))
          .toList(growable: false);

      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _links = links;
      _currentPage = page;
      _hasMore = body.hasNonNullField('next');
      _totalCount = body.field('count').integer();
    } on Exception catch (error) {
      if (!_isCurrentLinksFetch(fetchEpoch, stateEpoch)) {
        return;
      }
      _recordFailure(error, endpoint: 'GET /monitoring/links/');
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
    } on Exception catch (error) {
      _error = describeDataError(error);
      _recordFailure(error, endpoint: 'POST /monitoring/links/');
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
      final selectorsChanged =
          strategyClass == generalSelectorStrategy &&
          !listEquals(normalizeSelectors(selectorsText), link.selectors);

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
    } on Exception catch (error) {
      _error = describeDataError(error);
      _recordFailure(error, endpoint: 'PATCH /monitoring/links/{id}/');
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
      if (link.strategyId != null) {
        await _deleteStrategyIfUnused(jwt, link.strategyId!);
      }
      // If we deleted the last item on this page and it's not page 1,
      // fall back to the previous page — the current page is now empty.
      final targetPage = _links.length == 1 && _currentPage > 1
          ? _currentPage - 1
          : _currentPage;
      await goToPage(targetPage);
      return true;
    } on Exception catch (error) {
      _error = describeDataError(error);
      _recordFailure(error, endpoint: 'DELETE /monitoring/links/{id}/');
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
        body: linkId == null ? const <String, Object?>{} : {'link_id': linkId},
      );

      final data = expectSuccessObject(response, 'Trigger scrape');
      await fetchLinks();
      return _formatScrapeResult(data, linkId: linkId);
    } on Exception catch (error) {
      _error = describeDataError(error);
      _recordFailure(error, endpoint: 'POST /monitoring/trigger-scrape/');
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
    final strategy = StrategyRecord.fromJson(
      expectSuccessObject(
        response,
        'Create strategy',
        successCodes: const {200, 201},
      ),
    );
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
    required Map<String, Object?> strategyData,
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

  Future<void> _deleteStrategyIfUnused(JWT jwt, int strategyId) async {
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
    } on Exception catch (error) {
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

    final strategies = expectSuccessArray(
      response,
      'Fetch strategies',
    ).items().map(StrategyRecord.fromJson).toList(growable: false);

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

  Future<void> _fetchStrategyChoices(JWT jwt, {required int stateEpoch}) async {
    try {
      final response = await apiGet(
        '/monitoring/strat-choices',
        settings: _settings,
        headers: _authHeaders(jwt),
      );

      final choices = expectSuccessArray(response, 'Fetch strategy choices')
          .items()
          .map((value) => value.string(allowEmpty: false))
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

      if (!_isCurrentState(stateEpoch)) {
        return;
      }
      _strategyChoices = choices.isEmpty
          ? defaultStrategyChoices
          : List<String>.from(choices);
      _strategyChoicesLoaded = true;
    } on Exception catch (error) {
      if (!_isCurrentState(stateEpoch)) {
        return;
      }
      if (kDebugMode) {
        debugPrint('LinkService._fetchStrategyChoices: $error');
      }
      // Reported, not just logged: falling back to a single hardcoded choice
      // silently degrades the strategy dropdown, so a contract break here was
      // previously invisible outside a debug build.
      _recordFailure(error, endpoint: 'GET /monitoring/strat-choices');
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

enum NotifSort {
  newest('-update__created_at,-pk', 'Newest'),
  oldest('update__created_at,pk', 'Oldest')
  ;

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
  int get totalPages => _totalCount == 0 ? 1 : (_totalCount / _pageSize).ceil();
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

      final body = expectSuccessObject(response, 'Fetch notifications');
      final notifications = body
          .field('results')
          .items()
          .map(NotificationItem.fromJson)
          .toList(growable: false);

      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _notifications = notifications;
      _currentPage = 1;
      _hasMore = body.hasNonNullField('next');
      _totalCount = body.field('count').integer();
      _totalUnreadCount = body.field('unread_count').integer();
    } on Exception catch (error) {
      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _recordFailure(error, endpoint: 'GET /monitoring/notifications/');
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

      final body = expectSuccessObject(
        response,
        'Fetch notifications page $page',
      );
      final notifications = body
          .field('results')
          .items()
          .map(NotificationItem.fromJson)
          .toList(growable: false);

      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _notifications = notifications;
      _currentPage = page;
      _hasMore = body.hasNonNullField('next');
      _totalCount = body.field('count').integer();
      _totalUnreadCount =
          body.optionalField('unread_count')?.integer() ?? _totalUnreadCount;
    } on Exception catch (error) {
      if (_fetchEpoch != fetchEpoch) {
        return;
      }
      _recordFailure(error, endpoint: 'GET /monitoring/notifications/');
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
      _totalUnreadCount = (_totalUnreadCount + (wasUnread ? -1 : 1)).clamp(
        0,
        1 << 30,
      );
      return true;
    } on Exception catch (error) {
      _error = describeDataError(error);
      _recordFailure(error, endpoint: 'PATCH /monitoring/notifications/{id}/');
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
        body: const <String, Object?>{},
      );

      expectSuccessStatus(response, 'Mark all notifications as read');
      final now = DateTime.now();
      _notifications =
          _notifications
              .map(
                (item) =>
                    item.copyWith(status: NotificationStatus.read, readAt: now),
              )
              .toList(growable: false)
            ..sort(_compareNotifications);
      // Server clears all unread for the user, including pages we haven't
      // loaded; reflect that locally rather than counting visible items.
      _totalUnreadCount = 0;
    } on Exception catch (error) {
      _error = describeDataError(error);
      _recordFailure(
        error,
        endpoint: 'POST /monitoring/notifications/mark_all_read/',
      );
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

Map<String, Object?> buildStrategyData({
  required String strategyClass,
  required String selectorsText,
}) {
  if (strategyClass == generalSelectorStrategy) {
    return <String, Object?>{'selectors': normalizeSelectors(selectorsText)};
  }

  return <String, Object?>{};
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
  return AppFailure.from(error).userMessage;
}

Map<String, String> _authHeaders(JWT jwt) {
  return <String, String>{
    'Authorization': 'Bearer ${jwt.access}',
    'Content-Type': _jsonContentType,
  };
}

int _compareNotifications(NotificationItem left, NotificationItem right) {
  if (left.isUnread != right.isUnread) {
    return left.isUnread ? -1 : 1;
  }
  return right.createdAt.compareTo(left.createdAt);
}

String _formatScrapeResult(JsonCursor data, {required int? linkId}) {
  if (linkId != null) {
    final status = data.field('status').string(allowEmpty: false);
    if (status == 'ok') {
      final updatesFound = data.optionalField('updates_found')?.integer() ?? 0;
      return updatesFound == 0
          ? 'Scrape finished. No new updates were found.'
          : 'Scrape finished. Found $updatesFound new '
                '${updatesFound == 1 ? 'update' : 'updates'}.';
    }
    return extractErrorMessage(data.object()) ?? 'Scrape failed.';
  }

  var okCount = 0;
  var totalUpdates = 0;
  var failedCount = 0;

  final results = data.optionalField('results');
  for (final key in results?.object().keys ?? const <String>[]) {
    final value = results!.field(key);
    final status = value.optionalField('status')?.string() ?? '';
    if (status == 'ok') {
      okCount += 1;
      totalUpdates += value.optionalField('updates_found')?.integer() ?? 0;
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
