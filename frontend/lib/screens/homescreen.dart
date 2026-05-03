import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/commons/url_launcher_helper.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshDashboard();
    });
  }

  Future<void> _refreshDashboard() async {
    final futures = <Future<void>>[
      context.read<LinkService>().fetchLinks(),
      context.read<NotificationService>().fetchNotifications(),
    ];

    final authService = context.read<AuthService>();
    if (authService.jwt != null) {
      futures.add(context.read<UserDataService>().getUserInfo());
    }

    await Future.wait(futures);
  }

  Future<void> _handleScrapeAll() async {
    final linkService = context.read<LinkService>();
    final notificationService = context.read<NotificationService>();
    final message = await linkService.triggerScrape();
    if (message != null) {
      await notificationService.fetchNotifications();
    }
    if (!mounted) return;
    _showMessage(message ?? linkService.error);
  }

  Future<void> _handleScrapeLink(Link link) async {
    final linkService = context.read<LinkService>();
    final notificationService = context.read<NotificationService>();
    final message = await linkService.triggerScrape(linkId: link.id);
    if (message != null) {
      await notificationService.fetchNotifications();
    }
    if (!mounted) return;
    _showMessage(message ?? linkService.error);
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('That URL could not be opened.');
      return;
    }
    await openUriSafely(context, uri);
  }

  Future<void> _handleNotificationTap(NotificationItem notification) async {
    final notificationService = context.read<NotificationService>();
    if (notification.isUnread) {
      await notificationService.markRead(notification.id);
    }
    if (!mounted || notification.itemUrl.isEmpty) return;
    await _openExternalUrl(notification.itemUrl);
  }

  Future<void> _handleNotificationMarkRead(int id) async {
    final notificationService = context.read<NotificationService>();
    await notificationService.markRead(id);
    if (!mounted) return;
    _showMessage('Marked as read.');
  }

  Future<void> _handleNotificationOpenUrl(String url) async {
    await _openExternalUrl(url);
  }

  void _logout() {
    context.read<AuthService>().logout();
    context.go('/login');
  }

  void _showMessage(String? message) {
    if (!mounted || message == null || message.trim().isEmpty) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: SelectableText(message.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final appSettings = context.watch<AppSettingsController?>();
    final userData = context.watch<UserDataService>().userData;
    final linkService = context.watch<LinkService>();
    final notificationService = context.watch<NotificationService>();

    return Scaffold(
      backgroundColor: tokens.bg0,
      body: Stack(
        children: [
          if (appSettings?.designDitheringEnabled ?? true)
            const DitherOverlay(),
          SafeArea(
            child: _HomeConsole(
              appSettings: appSettings,
              userData: userData,
              linkService: linkService,
              notificationService: notificationService,
              onRefresh: _refreshDashboard,
              onScrapeAll: linkService.scrapingAll ? null : _handleScrapeAll,
              onScrapeLink: _handleScrapeLink,
              onNotificationTap: _handleNotificationTap,
              onNotificationMarkRead: _handleNotificationMarkRead,
              onNotificationOpenUrl: _handleNotificationOpenUrl,
              onMarkAllRead: notificationService.unreadCount == 0 ||
                      notificationService.markingAllRead
                  ? null
                  : notificationService.markAllRead,
              onSources: () => context.go('/sources'),
              onSettings: () => context.push('/settings'),
              onAbout: () => context.push('/about'),
              onLogout: _logout,
            ),
          ),
        ],
      ),
    );
  }
}

class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LinkService>().fetchLinks();
    });
  }

  Future<void> _handleAddLink() async {
    final linkService = context.read<LinkService>();
    await linkService.ensureStrategyChoicesLoaded();
    if (!mounted) return;

    final draft = await showDialog<_LinkDraft>(
      context: context,
      builder: (_) =>
          _LinkEditorDialog(strategyChoices: linkService.strategyChoices),
    );
    if (draft == null) return;

    final success = await linkService.createLink(
      name: draft.name,
      url: draft.url,
      strategyClass: draft.strategyClass,
      selectorsText: draft.selectorsText,
    );
    if (!mounted) return;

    _showMessage(success ? 'Source added.' : linkService.error);
  }

  Future<void> _handleEditLink(Link link) async {
    final linkService = context.read<LinkService>();
    await linkService.ensureStrategyChoicesLoaded();
    if (!mounted) return;

    final draft = await showDialog<_LinkDraft>(
      context: context,
      builder: (_) => _LinkEditorDialog(
        strategyChoices: linkService.strategyChoices,
        initialValue: _LinkDraft(
          name: link.name,
          url: link.url,
          strategyClass: link.strategyClass,
          selectorsText: link.selectors.join('\n'),
        ),
        submitLabel: 'Save',
        title: 'Edit source',
      ),
    );
    if (draft == null) return;

    final success = await linkService.updateLink(
      link: link,
      name: draft.name,
      url: draft.url,
      strategyClass: draft.strategyClass,
      selectorsText: draft.selectorsText,
    );
    if (!mounted) return;

    _showMessage(success ? 'Source updated.' : linkService.error);
  }

  Future<void> _handleDeleteLink(Link link) async {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final linkService = context.read<LinkService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete source'),
        content: Text('Remove "${link.name}" from the registry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: tokens.bg1,
              backgroundColor: NotifFeedback.error,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              textStyle: text$.eyebrow,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await linkService.deleteLink(link);
    if (!mounted) return;

    _showMessage(success ? 'Source removed.' : linkService.error);
  }

  Future<void> _handleScrapeLink(Link link) async {
    final linkService = context.read<LinkService>();
    final notificationService = context.read<NotificationService>();
    final message = await linkService.triggerScrape(linkId: link.id);
    if (message != null) {
      await notificationService.fetchNotifications();
    }
    if (!mounted) return;
    _showMessage(message ?? linkService.error);
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('That URL could not be opened.');
      return;
    }

    await openUriSafely(context, uri);
  }

  void _showMessage(String? message) {
    if (!mounted || message == null || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: SelectableText(message.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final appSettings = context.watch<AppSettingsController?>();
    final linkService = context.watch<LinkService>();

    return Scaffold(
      backgroundColor: tokens.bg0,
      appBar: AppBar(
        backgroundColor: tokens.bg1,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Home',
          onPressed: () => context.go('/home'),
          icon: Icon(Icons.arrow_back_sharp, color: tokens.inkDim),
        ),
        title: Row(
          children: [
            Text(
              'Notif',
              style: text$.heading.copyWith(
                color: tokens.ink,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 8),
            Text('/ sources', style: text$.micro.copyWith(color: tokens.inkMute)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: Icon(Icons.settings_sharp, color: tokens.inkDim),
          ),
          IconButton(
            tooltip: 'About',
            onPressed: () => context.push('/about'),
            icon: Icon(Icons.info_outline, color: tokens.inkDim),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tokens.rule),
        ),
      ),
      body: Stack(
        children: [
          if (appSettings?.designDitheringEnabled ?? true)
            const DitherOverlay(),
          SafeArea(
            child: RefreshIndicator(
              color: tokens.accent,
              backgroundColor: tokens.bg2,
              onRefresh: linkService.fetchLinks,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow(
                              'Registry',
                              tone: EyebrowTone.accent,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sources are managed here, not in the feed.',
                              style: text$.title.copyWith(
                                color: tokens.ink,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      NotifButton(
                        label: 'Add source',
                        icon: Icons.add_sharp,
                        onPressed: linkService.creating ? null : _handleAddLink,
                      ),
                    ],
                  ),
                  if (linkService.error != null) ...[
                    const SizedBox(height: 18),
                    _ErrorBanner(message: linkService.error!),
                  ],
                  const SizedBox(height: 24),
                  if (linkService.loading && linkService.links.isEmpty)
                    const _LoadingState(message: 'Loading sources...')
                  else if (linkService.links.isEmpty)
                    _EmptyState(
                      icon: Icons.link_off_sharp,
                      title: 'No sources yet',
                      message:
                          'Add a monitored page to start collecting updates.',
                      action: NotifButton(
                        label: 'Add source',
                        icon: Icons.add_sharp,
                        onPressed: linkService.creating ? null : _handleAddLink,
                      ),
                    )
                  else
                    for (final link in linkService.links) ...[
                      _LinkCard(
                        link: link,
                        isScraping: linkService.isScrapingLink(link.id),
                        isSaving: linkService.isUpdatingLink(link.id),
                        isDeleting: linkService.isDeletingLink(link.id),
                        onScrape: () => _handleScrapeLink(link),
                        onEdit: () => _handleEditLink(link),
                        onDelete: () => _handleDeleteLink(link),
                        onOpen: () => _openExternalUrl(link.url),
                      ),
                      if (link != linkService.links.last)
                        const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeConsole extends StatelessWidget {
  const _HomeConsole({
    required this.appSettings,
    required this.userData,
    required this.linkService,
    required this.notificationService,
    required this.onRefresh,
    required this.onScrapeAll,
    required this.onScrapeLink,
    required this.onNotificationTap,
    required this.onNotificationMarkRead,
    required this.onNotificationOpenUrl,
    required this.onMarkAllRead,
    required this.onSources,
    required this.onSettings,
    required this.onAbout,
    required this.onLogout,
  });

  final AppSettingsController? appSettings;
  final UserData? userData;
  final LinkService linkService;
  final NotificationService notificationService;
  final Future<void> Function() onRefresh;
  final VoidCallback? onScrapeAll;
  final Future<void> Function(Link link) onScrapeLink;
  final Future<void> Function(NotificationItem notification) onNotificationTap;
  final Future<void> Function(int id) onNotificationMarkRead;
  final Future<void> Function(String url) onNotificationOpenUrl;
  final VoidCallback? onMarkAllRead;
  final VoidCallback onSources;
  final VoidCallback onSettings;
  final VoidCallback onAbout;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final density = appSettings?.homeDensity ?? HomeDensity.compact;
        final metrics = _HomeConsoleMetrics.forDensity(
          isDesktop ? density : HomeDensity.dense,
        );

        return Column(
          children: [
            _ConsoleTopBar(
              density: density,
              metrics: metrics,
              userData: userData,
              unreadCount: notificationService.unreadCount,
              sourceCount: linkService.links.length,
              backendLabel: _backendModeLabel(appSettings),
              syncLabel: _lastScrapeLabel(linkService.links),
              scrapeBusy: linkService.scrapingAll,
              onScrape: onScrapeAll,
              onHome: null,
              onSources: onSources,
              onSettings: onSettings,
              onAbout: onAbout,
              onLogout: onLogout,
              onDensityChanged: appSettings?.setHomeDensity,
              activeSection: 'home',
            ),
            if (linkService.error != null || notificationService.error != null)
              _ConsoleErrorStrip(
                linkError: linkService.error,
                notificationError: notificationService.error,
              ),
            Expanded(
              child: isDesktop
                  ? Row(
                      children: [
                        SizedBox(
                          width: metrics.railWidth,
                          child: _ConsoleSourceRail(
                            metrics: metrics,
                            links: linkService.links,
                            loading: linkService.loading,
                            onSources: onSources,
                            onScrapeLink: onScrapeLink,
                            isScrapingLink: linkService.isScrapingLink,
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: tokens.rule,
                        ),
                        Expanded(
                          child: _UpdateConsole(
                            metrics: metrics,
                            notifications: notificationService.notifications,
                            loading: notificationService.loading,
                            unreadCount: notificationService.unreadCount,
                            markingAllRead: notificationService.markingAllRead,
                            isMarkingRead: notificationService.isMarkingRead,
                            onRefresh: onRefresh,
                            onNotificationTap: onNotificationTap,
                            onNotificationMarkRead: onNotificationMarkRead,
                            onNotificationOpenUrl: onNotificationOpenUrl,
                            onMarkAllRead: onMarkAllRead,
                            onSources: onSources,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _MobileSourceSummary(
                          metrics: metrics,
                          links: linkService.links,
                          loading: linkService.loading,
                          onSources: onSources,
                        ),
                        Expanded(
                          child: _UpdateConsole(
                            metrics: metrics,
                            notifications: notificationService.notifications,
                            loading: notificationService.loading,
                            unreadCount: notificationService.unreadCount,
                            markingAllRead:
                                notificationService.markingAllRead,
                            isMarkingRead: notificationService.isMarkingRead,
                            onRefresh: onRefresh,
                            onNotificationTap: onNotificationTap,
                            onNotificationMarkRead: onNotificationMarkRead,
                            onNotificationOpenUrl: onNotificationOpenUrl,
                            onMarkAllRead: onMarkAllRead,
                            onSources: onSources,
                            mobileTui: true,
                          ),
                        ),
                        _MobileCommandLine(
                          metrics: metrics,
                          count: notificationService.notifications.length,
                          onScrape: onScrapeAll,
                          onSources: onSources,
                          onSettings: onSettings,
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ConsoleTopBar extends StatelessWidget {
  const _ConsoleTopBar({
    required this.density,
    required this.metrics,
    required this.userData,
    required this.unreadCount,
    required this.sourceCount,
    required this.backendLabel,
    required this.syncLabel,
    required this.scrapeBusy,
    required this.onScrape,
    required this.onHome,
    required this.onSources,
    required this.onSettings,
    required this.onAbout,
    required this.onLogout,
    required this.onDensityChanged,
    required this.activeSection,
  });

  final HomeDensity density;
  final _HomeConsoleMetrics metrics;
  final UserData? userData;
  final int unreadCount;
  final int sourceCount;
  final String backendLabel;
  final String syncLabel;
  final bool scrapeBusy;
  final VoidCallback? onScrape;
  final VoidCallback? onHome;
  final VoidCallback? onSources;
  final VoidCallback onSettings;
  final VoidCallback onAbout;
  final VoidCallback onLogout;
  final ValueChanged<HomeDensity>? onDensityChanged;
  final String activeSection;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 1120;
    final username = userData?.username.trim();
    final identity = username == null || username.isEmpty ? 'operator' : username;
    final selectedHome = activeSection == 'home';
    final selectedSources = activeSection == 'sources';

    return Container(
      decoration: BoxDecoration(
        color: tokens.bg1.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: tokens.rule)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 18,
        vertical: compact ? 7 : metrics.topBarVPad,
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Notif',
                      style: text$.heading.copyWith(
                        color: tokens.ink,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const Spacer(),
                    _MiniStat(
                      metrics: metrics,
                      label: 'U',
                      value: '$unreadCount',
                      accent: true,
                    ),
                    _MiniStat(metrics: metrics, label: 'S', value: '$sourceCount'),
                    const SizedBox(width: 6),
                    _TopBarAction(
                      metrics: metrics,
                      label: scrapeBusy ? 'scraping' : 'scrape',
                      onPressed: onScrape,
                      accent: true,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _TopBarIconAction(
                      metrics: metrics,
                      icon: Icons.home_outlined,
                      tooltip: 'Home',
                      onPressed: onHome,
                      selected: selectedHome,
                    ),
                    _TopBarIconAction(
                      metrics: metrics,
                      icon: Icons.link_outlined,
                      tooltip: 'Sources',
                      onPressed: onSources,
                      selected: selectedSources,
                    ),
                    _TopBarIconAction(
                      metrics: metrics,
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onPressed: onSettings,
                    ),
                    _TopBarIconAction(
                      metrics: metrics,
                      icon: Icons.info_outline,
                      tooltip: 'About',
                      onPressed: onAbout,
                    ),
                    _TopBarIconAction(
                      metrics: metrics,
                      icon: Icons.logout_outlined,
                      tooltip: 'Logout',
                      onPressed: onLogout,
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Text(
                  'Notif',
                  style: text$.heading.copyWith(
                    color: tokens.ink,
                    fontStyle: FontStyle.italic,
                    fontSize: metrics.brandSize,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '~/notif/$activeSection',
                  style: text$.micro.copyWith(
                    color: tokens.inkMute,
                    letterSpacing: 0,
                    fontSize: metrics.microSize,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '@$identity',
                  style: text$.micro.copyWith(
                    color: tokens.inkDim,
                    fontSize: metrics.microSize,
                  ),
                ),
                const Spacer(),
                _MiniStat(
                  metrics: metrics,
                  label: 'UNREAD',
                  value: '$unreadCount',
                  accent: true,
                ),
                _MiniStat(metrics: metrics, label: 'SRC', value: '$sourceCount'),
                _MiniStat(metrics: metrics, label: 'SYNC', value: syncLabel),
                _MiniStat(metrics: metrics, label: 'API', value: backendLabel),
                const SizedBox(width: 8),
                _DensitySegment(
                  selected: density,
                  onChanged: onDensityChanged,
                  metrics: metrics,
                ),
                _TopBarAction(
                  metrics: metrics,
                  label: scrapeBusy ? 'scraping' : 'scrape',
                  onPressed: onScrape,
                  accent: true,
                ),
                _TopBarAction(
                  metrics: metrics,
                  label: 'home',
                  onPressed: onHome,
                  selected: selectedHome,
                ),
                _TopBarAction(
                  metrics: metrics,
                  label: 'sources',
                  onPressed: onSources,
                  selected: selectedSources,
                ),
                _TopBarAction(
                  metrics: metrics,
                  label: 'settings',
                  onPressed: onSettings,
                ),
                _TopBarAction(metrics: metrics, label: 'about', onPressed: onAbout),
                _TopBarAction(
                  metrics: metrics,
                  label: 'logout',
                  onPressed: onLogout,
                ),
              ],
            ),
    );
  }
}

class _HomeConsoleMetrics {
  const _HomeConsoleMetrics({
    required this.railWidth,
    required this.brandSize,
    required this.bodySize,
    required this.microSize,
    required this.actionFontSize,
    required this.topBarVPad,
    required this.actionHPad,
    required this.actionVPad,
    required this.railRowVPad,
    required this.updateRowVPad,
    required this.headerHeight,
  });

  final double railWidth;
  final double brandSize;
  final double bodySize;
  final double microSize;
  final double actionFontSize;
  final double topBarVPad;
  final double actionHPad;
  final double actionVPad;
  final double railRowVPad;
  final double updateRowVPad;
  final double headerHeight;

  static _HomeConsoleMetrics forDensity(HomeDensity density) {
    switch (density) {
      case HomeDensity.comfortable:
        return const _HomeConsoleMetrics(
          railWidth: 336,
          brandSize: 31,
          bodySize: 20,
          microSize: 15,
          actionFontSize: 14,
          topBarVPad: 14,
          actionHPad: 15,
          actionVPad: 9,
          railRowVPad: 14,
          updateRowVPad: 14,
          headerHeight: 52,
        );
      case HomeDensity.compact:
        return const _HomeConsoleMetrics(
          railWidth: 252,
          brandSize: 24,
          bodySize: 16,
          microSize: 13,
          actionFontSize: 12,
          topBarVPad: 9,
          actionHPad: 10,
          actionVPad: 6,
          railRowVPad: 7,
          updateRowVPad: 7,
          headerHeight: 37,
        );
      case HomeDensity.dense:
        return const _HomeConsoleMetrics(
          railWidth: 224,
          brandSize: 21,
          bodySize: 14.5,
          microSize: 11.5,
          actionFontSize: 10.5,
          topBarVPad: 7,
          actionHPad: 8,
          actionVPad: 4,
          railRowVPad: 5,
          updateRowVPad: 5,
          headerHeight: 32,
        );
    }
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.metrics,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final _HomeConsoleMetrics metrics;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: RichText(
        text: TextSpan(
          style: text$.micro.copyWith(
            color: tokens.inkMute,
            fontSize: metrics.microSize,
          ),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: accent ? tokens.accent : tokens.ink,
                fontSize: metrics.microSize + 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarAction extends StatelessWidget {
  const _TopBarAction({
    required this.metrics,
    required this.label,
    this.onPressed,
    this.accent = false,
    this.selected = false,
  });

  final _HomeConsoleMetrics metrics;
  final String label;
  final VoidCallback? onPressed;
  final bool accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final foreground = accent ? tokens.btnInk : tokens.ink;
    final background = accent
        ? tokens.btnBg
        : selected
        ? tokens.bg2
        : tokens.bg1;
    final border = accent || selected ? tokens.ruleStrong : tokens.rule;

    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.actionHPad,
            vertical: metrics.actionVPad,
          ),
          decoration: BoxDecoration(
            color: onPressed == null
                ? tokens.rule.withValues(alpha: 0.16)
                : background,
            border: Border.all(color: border),
          ),
          child: Text(
            label.toUpperCase(),
            style: text$.eyebrow.copyWith(
              color: onPressed == null ? tokens.inkMute : foreground,
              letterSpacing: 0,
              fontSize: metrics.actionFontSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBarIconAction extends StatelessWidget {
  const _TopBarIconAction({
    required this.metrics,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final _HomeConsoleMetrics metrics;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final background = selected ? tokens.bg2 : tokens.bg1;
    final border = selected ? tokens.ruleStrong : tokens.rule;
    final foreground = onPressed == null ? tokens.inkMute : tokens.ink;

    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: onPressed == null
                  ? tokens.rule.withValues(alpha: 0.16)
                  : background,
              border: Border.all(color: border),
            ),
            child: Icon(
              icon,
              size: metrics.actionFontSize + 6,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _DensitySegment extends StatelessWidget {
  const _DensitySegment({
    required this.selected,
    required this.onChanged,
    required this.metrics,
  });

  final HomeDensity selected;
  final ValueChanged<HomeDensity>? onChanged;
  final _HomeConsoleMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: tokens.bg0.withValues(alpha: 0.35),
        border: Border.all(color: tokens.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final density in HomeDensity.values)
            InkWell(
              onTap: onChanged == null ? null : () => onChanged!(density),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.actionHPad - 1,
                  vertical: metrics.actionVPad,
                ),
                decoration: BoxDecoration(
                  color: density == selected ? tokens.accent : Colors.transparent,
                  border: Border(
                    left: density == HomeDensity.comfortable
                        ? BorderSide.none
                        : BorderSide(color: tokens.rule),
                  ),
                ),
                child: Text(
                  switch (density) {
                    HomeDensity.comfortable => 'COMF',
                    HomeDensity.compact => 'COMP',
                    HomeDensity.dense => 'DENSE',
                  },
                  style: text$.micro.copyWith(
                    color: density == selected ? tokens.bg0 : tokens.inkDim,
                    fontSize: metrics.microSize,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsoleSourceRail extends StatelessWidget {
  const _ConsoleSourceRail({
    required this.metrics,
    required this.links,
    required this.loading,
    required this.onSources,
    required this.onScrapeLink,
    required this.isScrapingLink,
  });

  final _HomeConsoleMetrics metrics;
  final List<Link> links;
  final bool loading;
  final VoidCallback onSources;
  final Future<void> Function(Link link) onScrapeLink;
  final bool Function(int id) isScrapingLink;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      color: tokens.bg1.withValues(alpha: 0.82),
      child: Column(
        children: [
          InkWell(
            onTap: onSources,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: metrics.actionVPad + 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'registry - ${links.length}',
                      style: text$.micro.copyWith(
                        color: tokens.inkMute,
                        fontSize: metrics.microSize,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.actionHPad,
                      vertical: metrics.actionVPad,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.btnBg,
                      border: Border.all(color: tokens.ruleStrong),
                    ),
                    child: Text(
                      '+ MANAGE',
                      style: text$.micro.copyWith(
                        color: tokens.btnInk,
                        fontSize: metrics.microSize,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: tokens.rule),
          Expanded(
            child: loading && links.isEmpty
                ? const _LoadingState(message: 'Loading sources...')
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: links.isEmpty ? 1 : links.length,
                    itemBuilder: (context, index) {
                      if (links.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No sources. Open registry to add one.',
                            style: text$.body.copyWith(
                              color: tokens.inkDim,
                              fontSize: metrics.bodySize,
                            ),
                          ),
                        );
                      }

                      final link = links[index];
                      final busy = isScrapingLink(link.id);

                      return _SourceRailRow(
                        metrics: metrics,
                        link: link,
                        busy: busy,
                        onTap: onSources,
                        onScrape: busy ? null : () => onScrapeLink(link),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SourceRailRow extends StatelessWidget {
  const _SourceRailRow({
    required this.metrics,
    required this.link,
    required this.busy,
    required this.onTap,
    required this.onScrape,
  });

  final _HomeConsoleMetrics metrics;
  final Link link;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onScrape;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: metrics.railRowVPad,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StatusDot(
                state: link.lastScraped == null
                    ? StatusDotState.idle
                    : StatusDotState.synced,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text$.body.copyWith(
                      color: tokens.ink,
                      fontSize: metrics.bodySize,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${link.strategyLabel} - ${_formatTimeAgo(link.lastScraped)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text$.micro.copyWith(
                      color: tokens.inkMute,
                      letterSpacing: 0,
                      fontSize: metrics.microSize,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onScrape,
              child: busy
                  ? GestureDetector(
                      onTap: () {},
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.accent,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.radar_sharp,
                      size: metrics.bodySize + 2,
                      color: tokens.inkMute,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSourceSummary extends StatelessWidget {
  const _MobileSourceSummary({
    required this.metrics,
    required this.links,
    required this.loading,
    required this.onSources,
  });

  final _HomeConsoleMetrics metrics;
  final List<Link> links;
  final bool loading;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final visibleLinks = links.take(4).toList(growable: false);

    return InkWell(
      onTap: onSources,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: tokens.bg1.withValues(alpha: 0.72),
          border: Border(bottom: BorderSide(color: tokens.rule)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
        child: loading && links.isEmpty
            ? Text(
                'loading sources...',
                style: text$.micro.copyWith(
                  color: tokens.inkMute,
                  fontSize: metrics.microSize,
                ),
              )
            : Column(
                children: [
                  for (final link in visibleLinks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          StatusDot(
                            state: link.lastScraped == null
                                ? StatusDotState.idle
                                : StatusDotState.synced,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            link.strategyLabel.toLowerCase(),
                            style: text$.micro.copyWith(
                              color: tokens.accent,
                              fontSize: metrics.microSize,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              link.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text$.micro.copyWith(
                                color: tokens.inkDim,
                                letterSpacing: 0,
                                fontSize: metrics.microSize,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          links.length > visibleLinks.length
                              ? '+ ${links.length - visibleLinks.length} more sources'
                              : '${links.length} sources',
                          style: text$.micro.copyWith(
                            color: tokens.inkMute,
                            fontSize: metrics.microSize,
                          ),
                        ),
                      ),
                      Text(
                        ':sources',
                        style: text$.micro.copyWith(
                          color: tokens.accent,
                          fontSize: metrics.microSize,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _UpdateConsole extends StatelessWidget {
  const _UpdateConsole({
    required this.metrics,
    required this.notifications,
    required this.loading,
    required this.unreadCount,
    required this.markingAllRead,
    required this.isMarkingRead,
    required this.onRefresh,
    required this.onNotificationTap,
    required this.onNotificationMarkRead,
    required this.onNotificationOpenUrl,
    required this.onMarkAllRead,
    required this.onSources,
    this.mobileTui = false,
  });

  final _HomeConsoleMetrics metrics;
  final List<NotificationItem> notifications;
  final bool loading;
  final int unreadCount;
  final bool markingAllRead;
  final bool Function(int id) isMarkingRead;
  final Future<void> Function() onRefresh;
  final Future<void> Function(NotificationItem notification) onNotificationTap;
  final Future<void> Function(int id) onNotificationMarkRead;
  final Future<void> Function(String url) onNotificationOpenUrl;
  final VoidCallback? onMarkAllRead;
  final VoidCallback onSources;
  final bool mobileTui;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final items = notifications;

    return RefreshIndicator(
      color: tokens.accent,
      backgroundColor: tokens.bg2,
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          if (!mobileTui)
            SliverToBoxAdapter(
              child: _ConsoleMasthead(
                metrics: metrics,
                unreadCount: unreadCount,
                totalCount: items.length,
                onScrape: onRefresh,
                onSources: onSources,
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ConsoleHeaderDelegate(
              metrics: metrics,
              mobileTui: mobileTui,
              unreadCount: unreadCount,
              markingAllRead: markingAllRead,
              onMarkAllRead: onMarkAllRead,
            ),
          ),
          if (loading && items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _LoadingState(message: 'Loading updates...'),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _EmptyState(
                  icon: Icons.mark_email_read_outlined,
                  title: 'No updates yet',
                  message:
                      'Scrape your sources or add a new one to start filling the feed.',
                  action: NotifButton(
                    label: 'Manage sources',
                    icon: Icons.add_link_sharp,
                    onPressed: onSources,
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: mobileTui ? 10 : 14,
                      vertical: mobileTui ? 6 : metrics.updateRowVPad,
                    ),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: tokens.rule)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'EOF - ${items.length} entries',
                          style: text$.micro.copyWith(
                            color: tokens.inkMute,
                            fontSize: metrics.microSize,
                          ),
                        ),
                        const Spacer(),
                        if (!mobileTui)
                          Text(
                            'pull to refresh - enter opens browser',
                            style: text$.micro.copyWith(
                              color: tokens.inkMute,
                              fontSize: metrics.microSize,
                            ),
                          ),
                      ],
                    ),
                  );
                }

                final item = items[index];
                return _ConsoleNotificationRow(
                  notification: item,
                  metrics: metrics,
                  index: index,
                  mobileTui: mobileTui,
                  busy: isMarkingRead(item.id),
                  onTap: () => onNotificationTap(item),
                  onChipTap: item.isUnread
                      ? () => onNotificationMarkRead(item.id)
                      : item.itemUrl.isNotEmpty
                          ? () => onNotificationOpenUrl(item.itemUrl)
                          : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ConsoleMasthead extends StatelessWidget {
  const _ConsoleMasthead({
    required this.metrics,
    required this.unreadCount,
    required this.totalCount,
    required this.onScrape,
    required this.onSources,
  });

  final _HomeConsoleMetrics metrics;
  final int unreadCount;
  final int totalCount;
  final Future<void> Function() onScrape;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.actionHPad + 8,
        metrics.updateRowVPad + 6,
        metrics.actionHPad + 8,
        metrics.updateRowVPad + 4,
      ),
      child: NotifCard(
        cornerMarks: true,
        padding: EdgeInsets.all(metrics.actionHPad + 8),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Updates console', tone: EyebrowTone.accent),
                  const SizedBox(height: 10),
                  Text(
                    unreadCount == 0
                        ? 'Nothing urgent. Keep the feed quiet.'
                        : '$unreadCount unread signals need review.',
                    style: text$.title.copyWith(
                      color: tokens.ink,
                      fontStyle: FontStyle.italic,
                      fontSize: metrics.bodySize * 1.8,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$totalCount total entries in the local console. Sources live in their own registry; this page is for reading and clearing updates.',
                    style: text$.bodyLong.copyWith(
                      color: tokens.inkDim,
                      fontSize: metrics.bodySize,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      NotifButton(
                        label: 'Refresh feed',
                        icon: Icons.sync_sharp,
                        onPressed: onScrape,
                      ),
                      NotifButton(
                        label: 'Manage sources',
                        icon: Icons.add_link_sharp,
                        variant: NotifButtonVariant.ghost,
                        onPressed: onSources,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: 0.88,
                  child: _SignalOrb(
                    size: math.min(260, metrics.railWidth * 0.76),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsoleHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ConsoleHeaderDelegate({
    required this.metrics,
    required this.mobileTui,
    required this.unreadCount,
    required this.markingAllRead,
    required this.onMarkAllRead,
  });

  final _HomeConsoleMetrics metrics;
  final bool mobileTui;
  final int unreadCount;
  final bool markingAllRead;
  final VoidCallback? onMarkAllRead;

  @override
  double get minExtent => mobileTui ? 25 : metrics.headerHeight;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      color: tokens.bg0.withValues(alpha: 0.97),
      padding: EdgeInsets.symmetric(
        horizontal: mobileTui ? 10 : 14,
        vertical: mobileTui ? 4 : metrics.actionVPad,
      ),
      child: Row(
        children: [
          SizedBox(
            width: mobileTui ? 60 : 82,
            child: Text(
              't',
              style: text$.micro.copyWith(
                color: tokens.inkMute,
                fontSize: metrics.microSize,
              ),
            ),
          ),
          if (!mobileTui)
            SizedBox(
              width: 168,
              child: Text(
                'source',
                style: text$.micro.copyWith(
                  color: tokens.inkMute,
                  fontSize: metrics.microSize,
                ),
              ),
            ),
          Expanded(
            child: Text(
              mobileTui ? 'signal - source' : 'signal',
              style: text$.micro.copyWith(
                color: tokens.inkMute,
                fontSize: metrics.microSize,
              ),
            ),
          ),
          InkWell(
            onTap: onMarkAllRead,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.actionHPad,
                vertical: metrics.actionVPad,
              ),
              decoration: BoxDecoration(
                color: unreadCount > 0
                    ? tokens.bg1
                    : tokens.rule.withValues(alpha: 0.12),
                border: Border.all(
                  color: unreadCount > 0 ? tokens.ruleStrong : tokens.rule,
                ),
              ),
              child: Text(
                markingAllRead
                    ? 'WORKING'
                    : unreadCount > 0
                    ? 'READ ALL'
                    : 'CLEAR',
                textAlign: TextAlign.right,
                style: text$.micro.copyWith(
                  color: unreadCount > 0 ? tokens.accent : tokens.inkMute,
                  fontSize: metrics.microSize,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ConsoleHeaderDelegate oldDelegate) {
    return mobileTui != oldDelegate.mobileTui ||
        metrics != oldDelegate.metrics ||
        unreadCount != oldDelegate.unreadCount ||
        markingAllRead != oldDelegate.markingAllRead ||
        onMarkAllRead != oldDelegate.onMarkAllRead;
  }
}

class _ConsoleNotificationRow extends StatelessWidget {
  const _ConsoleNotificationRow({
    required this.notification,
    required this.metrics,
    required this.index,
    required this.mobileTui,
    required this.busy,
    required this.onTap,
    this.onChipTap,
  });

  final NotificationItem notification;
  final _HomeConsoleMetrics metrics;
  final int index;
  final bool mobileTui;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onChipTap;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final source = _notificationSource(notification);

    return InkWell(
      onTap: busy ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: index.isOdd ? tokens.bg1.withValues(alpha: 0.42) : null,
          border: Border(bottom: BorderSide(color: tokens.rule)),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: mobileTui ? 10 : 14,
          vertical: mobileTui ? 4 : metrics.updateRowVPad,
        ),
        child: mobileTui
            ? Row(
                children: [
                  _ReadPip(unread: notification.isUnread),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 46,
                    child: Text(
                      _formatTimeAgo(notification.createdAt),
                      style: text$.micro.copyWith(
                        color: tokens.inkMute,
                        letterSpacing: 0,
                        fontSize: metrics.microSize,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          _shortSource(source),
                          style: text$.micro.copyWith(
                            color: tokens.accent,
                            letterSpacing: 0,
                            fontSize: metrics.microSize,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text$.body.copyWith(
                              color: tokens.ink,
                              fontSize: metrics.bodySize,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: tokens.accent,
                      ),
                    )
                  else
                    Icon(Icons.north_east_sharp, size: 12, color: tokens.inkMute),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReadPip(unread: notification.isUnread),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(
                      _formatTimeAgo(notification.createdAt),
                      style: text$.micro.copyWith(
                        color: tokens.inkMute,
                        letterSpacing: 0,
                        fontSize: metrics.microSize,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 168,
                    child: Text(
                      _shortSource(source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text$.micro.copyWith(
                        color: tokens.accent,
                        letterSpacing: 0,
                        fontSize: metrics.microSize,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          flex: 3,
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text$.body.copyWith(
                              color: tokens.ink,
                              fontSize: metrics.bodySize,
                            ),
                          ),
                        ),
                        if (notification.description.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 4,
                            child: Text(
                              '- ${notification.description}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text$.micro.copyWith(
                                color: tokens.inkMute,
                                letterSpacing: 0,
                                fontSize: metrics.microSize,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 102,
                    child: busy
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: tokens.accent,
                              ),
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerRight,
                            child: InkWell(
                              onTap: onChipTap,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: metrics.actionHPad,
                                  vertical: metrics.actionVPad,
                                ),
                                decoration: BoxDecoration(
                                  color: notification.isUnread
                                      ? tokens.bg1
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: notification.isUnread
                                        ? tokens.ruleStrong
                                        : tokens.rule,
                                  ),
                                ),
                                child: Text(
                                  notification.isUnread ? 'READ' : 'OPEN',
                                  textAlign: TextAlign.right,
                                  style: text$.micro.copyWith(
                                    color: notification.isUnread
                                        ? tokens.accent
                                        : tokens.inkDim,
                                    letterSpacing: 0,
                                    fontSize: metrics.microSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ReadPip extends StatelessWidget {
  const _ReadPip({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);

    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unread ? tokens.accent : Colors.transparent,
        border: unread ? null : Border.all(color: tokens.ruleStrong),
      ),
    );
  }
}

class _SignalOrb extends StatelessWidget {
  const _SignalOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SignalOrbPainter(
          ink: tokens.ink,
          accent: tokens.accent,
        ),
      ),
    );
  }
}

class _SignalOrbPainter extends CustomPainter {
  const _SignalOrbPainter({
    required this.ink,
    required this.accent,
  });

  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 4.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radiusLimit = size.width / 2;
    final inkPaint = Paint();
    final accentPaint = Paint();

    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final dx = (x - center.dx) / radiusLimit;
        final dy = (y - center.dy) / radiusLimit;
        final distance = math.sqrt(dx * dx + dy * dy);
        final density = math.max(0, 1 - distance);
        final noise = _noise(x, y);
        if (noise >= density) continue;

        final point = Offset(x, y);
        final pointRadius = 0.8 + _noise(x + 1, y + 1) * 1.2;
        final isAccent = density > 0.62 && _noise(x + 13, y + 7) > 0.82;
        final color = (isAccent ? accent : ink).withValues(
          alpha: isAccent ? 0.74 : 0.84,
        );
        final paint = isAccent ? accentPaint : inkPaint;
        paint.color = color;
        canvas.drawCircle(point, pointRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignalOrbPainter oldDelegate) {
    return oldDelegate.ink != ink || oldDelegate.accent != accent;
  }

  double _noise(double x, double y) {
    final s = math.sin(x * 12.9898 + y * 78.233 + 215.37) * 43758.5453;
    return s - s.floorToDouble();
  }
}

class _MobileCommandLine extends StatelessWidget {
  const _MobileCommandLine({
    required this.metrics,
    required this.count,
    required this.onScrape,
    required this.onSources,
    required this.onSettings,
  });

  final _HomeConsoleMetrics metrics;
  final int count;
  final VoidCallback? onScrape;
  final VoidCallback onSources;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bg1,
        border: Border(top: BorderSide(color: tokens.rule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Text(
            ':',
            style: text$.micro.copyWith(
              color: tokens.accent,
              fontSize: metrics.microSize,
            ),
          ),
          const SizedBox(width: 8),
          _CommandTap(metrics: metrics, label: 'scrape', onTap: onScrape),
          _CommandTap(metrics: metrics, label: 'sources', onTap: onSources),
          _CommandTap(metrics: metrics, label: 'settings', onTap: onSettings),
          const Spacer(),
          Text(
            '$count',
            style: text$.micro.copyWith(
              color: tokens.inkMute,
              fontSize: metrics.microSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandTap extends StatelessWidget {
  const _CommandTap({
    required this.metrics,
    required this.label,
    required this.onTap,
  });

  final _HomeConsoleMetrics metrics;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: text$.micro.copyWith(
            color: onTap == null ? tokens.inkMute : tokens.inkDim,
            letterSpacing: 0,
            fontSize: metrics.microSize,
          ),
        ),
      ),
    );
  }
}

class _ConsoleErrorStrip extends StatelessWidget {
  const _ConsoleErrorStrip({
    required this.linkError,
    required this.notificationError,
  });

  final String? linkError;
  final String? notificationError;

  @override
  Widget build(BuildContext context) {
    final text$ = NotifTextTheme.of(context);
    final errors = [
      if (linkError != null) 'sources: $linkError',
      if (notificationError != null) 'updates: $notificationError',
    ];

    return Container(
      width: double.infinity,
      color: NotifFeedback.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: SelectableText(
        errors.join(' | '),
        maxLines: 2,
        style: text$.micro.copyWith(color: NotifFeedback.error),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.link,
    required this.isScraping,
    required this.isSaving,
    required this.isDeleting,
    required this.onScrape,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
  });

  final Link link;
  final bool isScraping;
  final bool isSaving;
  final bool isDeleting;
  final VoidCallback onScrape;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final busy = isScraping || isSaving || isDeleting;

    return NotifCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(link.name, style: text$.heading.copyWith(color: tokens.ink)),
                    const SizedBox(height: 6),
                    SelectableText(
                      link.url,
                      style: text$.code.copyWith(color: tokens.inkMute),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Tag(link.strategyLabel),
                        Tag(
                          link.lastScraped == null
                              ? 'Never scraped'
                              : 'Last scrape ${_formatTimeAgo(link.lastScraped!)}',
                          tone: TagTone.muted,
                        ),
                      ],
                    ),
                    if (link.selectors.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Selectors: ${link.selectors.join(', ')}',
                        style: text$.body.copyWith(color: tokens.inkDim),
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CardActionButton(
                icon: Icons.radar_sharp,
                label: 'Scrape',
                onPressed: busy ? null : onScrape,
              ),
              _CardActionButton(
                icon: Icons.open_in_new_sharp,
                label: 'Open',
                onPressed: busy ? null : onOpen,
              ),
              _CardActionButton(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onPressed: busy ? null : onEdit,
              ),
              _CardActionButton(
                icon: Icons.delete_outline_sharp,
                label: 'Delete',
                destructive: true,
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final foreground = destructive ? NotifFeedback.error : tokens.ink;
    final border = destructive
        ? NotifFeedback.error.withValues(alpha: onPressed == null ? 0.26 : 0.55)
        : tokens.ruleStrong;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        splashColor: foreground.withValues(alpha: 0.08),
        highlightColor: foreground.withValues(alpha: 0.04),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            color: onPressed == null
                ? tokens.rule.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: text$.micro.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(message, style: text$.body.copyWith(color: tokens.inkDim)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: tokens.inkMute),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: text$.title.copyWith(
              color: tokens.ink,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: text$.body.copyWith(color: tokens.inkDim),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NotifFeedback.error.withValues(alpha: 0.10),
        border: Border.all(color: NotifFeedback.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline_sharp,
              color: NotifFeedback.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: text$.body.copyWith(
                color: tokens.brightness == Brightness.dark
                    ? NotifFeedback.error
                    : tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkEditorDialog extends StatefulWidget {
  const _LinkEditorDialog({
    required this.strategyChoices,
    this.initialValue,
    this.title = 'Add link',
    this.submitLabel = 'Add',
  });

  final List<String> strategyChoices;
  final _LinkDraft? initialValue;
  final String title;
  final String submitLabel;

  @override
  State<_LinkEditorDialog> createState() => _LinkEditorDialogState();
}

class _LinkEditorDialogState extends State<_LinkEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _selectorsController;
  late String _selectedStrategy;

  List<String> get _availableStrategies => widget.strategyChoices.isEmpty
      ? defaultStrategyChoices
      : widget.strategyChoices;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _selectedStrategy = _availableStrategies.contains(initial?.strategyClass)
        ? initial!.strategyClass
        : _availableStrategies.first;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _urlController = TextEditingController(text: initial?.url ?? '');
    _selectorsController = TextEditingController(
      text: initial?.selectorsText.isNotEmpty == true
          ? initial!.selectorsText
          : 'body',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _selectorsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: _dialogInputDecoration(
                    context: context,
                    label: 'Name',
                    hint: 'Threadmarks, release feed, changelog...',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Give the link a name.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _urlController,
                  decoration: _dialogInputDecoration(
                    context: context,
                    label: 'URL',
                    hint: 'https://example.com/feed',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Add a URL to monitor.';
                    }
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                      return 'Enter a full URL, including https://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedStrategy,
                  decoration: _dialogInputDecoration(
                    context: context,
                    label: 'Strategy',
                  ),
                  items: _availableStrategies
                      .map(
                        (choice) => DropdownMenuItem<String>(
                          value: choice,
                          child: Text(formatStrategyClassName(choice)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedStrategy = value;
                      if (_selectedStrategy != generalSelectorStrategy &&
                          _selectorsController.text.trim().isEmpty) {
                        _selectorsController.text = 'body';
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                _StrategyDescription(strategyClass: _selectedStrategy),
                if (_selectedStrategy == generalSelectorStrategy) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _selectorsController,
                    maxLines: 4,
                    decoration: _dialogInputDecoration(
                      context: context,
                      label: 'CSS selectors',
                      hint: 'body\narticle.post-card',
                    ),
                    validator: (value) {
                      if (_selectedStrategy != generalSelectorStrategy) {
                        return null;
                      }
                      if (value == null || value.trim().isEmpty) {
                        return 'Add at least one selector.';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;

            Navigator.of(context).pop(
              _LinkDraft(
                name: _nameController.text.trim(),
                url: _urlController.text.trim(),
                strategyClass: _selectedStrategy,
                selectorsText: _selectorsController.text.trim(),
              ),
            );
          },
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

class _StrategyDescription extends StatelessWidget {
  const _StrategyDescription({required this.strategyClass});

  final String strategyClass;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Text(
      _strategyDescription(strategyClass),
      style: text$.body.copyWith(color: tokens.inkMute),
    );
  }
}

class _LinkDraft {
  const _LinkDraft({
    required this.name,
    required this.url,
    required this.strategyClass,
    required this.selectorsText,
  });

  final String name;
  final String url;
  final String strategyClass;
  final String selectorsText;
}

InputDecoration _dialogInputDecoration({
  required BuildContext context,
  required String label,
  String? hint,
}) {
  final tokens = NotifTokens.of(context);
  final text$ = NotifTextTheme.of(context);

  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: text$.body.copyWith(color: tokens.inkDim),
    hintStyle: text$.body.copyWith(color: tokens.inkMute),
    filled: true,
    fillColor: tokens.bg1,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: tokens.rule),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: tokens.accent, width: 2),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: NotifFeedback.error),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: NotifFeedback.error, width: 2),
    ),
  );
}

String _backendModeLabel(AppSettingsController? settings) {
  switch (settings?.backendUrlMode ?? BackendUrlMode.builtin) {
    case BackendUrlMode.builtin:
      return 'Built-in';
    case BackendUrlMode.customWithFallback:
      return 'Custom + fallback';
    case BackendUrlMode.customOnly:
      return 'Custom only';
  }
}

String _strategyDescription(String strategyClass) {
  switch (strategyClass) {
    case generalSelectorStrategy:
      return 'Hashes the selected elements. Good for pages where a stable CSS selector can isolate the content that matters.';
    case 'SBSVThreadmarksStrategy':
      return 'Targets XenForo threadmark feeds on SpaceBattles and Sufficient Velocity.';
    case 'QQAlertsStrategy':
      return 'Pulls likely story-update alerts from Questionable Questing notifications.';
    case 'KemonoFavouritesStrategy':
      return 'Monitors favourites activity on Kemono-style pages.';
    default:
      return 'Uses the backend strategy implementation with its default configuration.';
  }
}

String _lastScrapeLabel(List<Link> links) {
  final scraped = links
      .map((link) => link.lastScraped)
      .whereType<DateTime>()
      .toList(growable: false);
  if (scraped.isEmpty) return 'never';
  scraped.sort((a, b) => b.compareTo(a));
  return _formatTimeAgo(scraped.first).replaceAll(' ago', '');
}

String _notificationSource(NotificationItem notification) {
  final uri = Uri.tryParse(notification.itemUrl);
  final host = uri?.host;
  if (host != null && host.isNotEmpty) {
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  final title = notification.title.trim();
  final separator = title.indexOf(':');
  if (separator > 0 && separator < 32) {
    return title.substring(0, separator);
  }
  return 'update';
}

String _shortSource(String source) {
  final normalized = source.toLowerCase();
  if (normalized.contains('spacebattles')) return 'sb';
  if (normalized.contains('sufficientvelocity')) return 'sv';
  if (normalized.contains('questionablequesting')) return 'qq';
  if (normalized.contains('daringfireball')) return 'df';
  if (normalized.contains('ycombinator')) return 'hn';
  if (normalized.contains('github')) return 'gh';
  if (normalized.contains('kemono')) return 'kemono';
  if (normalized.contains('.')) return normalized.split('.').first;
  return normalized.length <= 12 ? normalized : normalized.substring(0, 12);
}

String _formatTimeAgo(DateTime? dateTime) {
  if (dateTime == null) return 'never';
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}
