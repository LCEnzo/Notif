import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
      if (!mounted) {
        return;
      }
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

  Future<void> _handleAddLink() async {
    final linkService = context.read<LinkService>();
    await linkService.ensureStrategyChoicesLoaded();
    if (!mounted) {
      return;
    }

    final draft = await showDialog<_LinkDraft>(
      context: context,
      builder: (_) =>
          _LinkEditorDialog(strategyChoices: linkService.strategyChoices),
    );
    if (draft == null) {
      return;
    }

    final success = await linkService.createLink(
      name: draft.name,
      url: draft.url,
      strategyClass: draft.strategyClass,
      selectorsText: draft.selectorsText,
    );
    if (!mounted) {
      return;
    }

    _showMessage(success ? 'Link added to the registry.' : linkService.error);
  }

  Future<void> _handleEditLink(Link link) async {
    final linkService = context.read<LinkService>();
    await linkService.ensureStrategyChoicesLoaded();
    if (!mounted) {
      return;
    }

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
        title: 'Edit link',
      ),
    );
    if (draft == null) {
      return;
    }

    final success = await linkService.updateLink(
      link: link,
      name: draft.name,
      url: draft.url,
      strategyClass: draft.strategyClass,
      selectorsText: draft.selectorsText,
    );
    if (!mounted) {
      return;
    }

    _showMessage(success ? 'Link updated.' : linkService.error);
  }

  Future<void> _handleDeleteLink(Link link) async {
    final linkService = context.read<LinkService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete link'),
        content: Text(
          'Remove "${link.name}" from the registry? This only deletes the link entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FeedbackColors.error,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final success = await linkService.deleteLink(link);
    if (!mounted) {
      return;
    }

    _showMessage(success ? 'Link removed.' : linkService.error);
  }

  Future<void> _handleScrapeAll() async {
    final linkService = context.read<LinkService>();
    final notificationService = context.read<NotificationService>();
    final message = await linkService.triggerScrape();
    if (message != null) {
      await notificationService.fetchNotifications();
    }
    if (!mounted) {
      return;
    }
    _showMessage(message ?? linkService.error);
  }

  Future<void> _handleScrapeLink(Link link) async {
    final linkService = context.read<LinkService>();
    final notificationService = context.read<NotificationService>();
    final message = await linkService.triggerScrape(linkId: link.id);
    if (message != null) {
      await notificationService.fetchNotifications();
    }
    if (!mounted) {
      return;
    }
    _showMessage(message ?? linkService.error);
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('That URL could not be opened.');
      return;
    }

    if (await launchUrl(uri)) {
      return;
    }

    if (!mounted) {
      return;
    }
    _showMessage('Could not open $url');
  }

  Future<void> _handleNotificationTap(NotificationItem notification) async {
    final notificationService = context.read<NotificationService>();
    if (notification.isUnread) {
      await notificationService.markRead(notification.id);
    }
    if (!mounted || notification.itemUrl.isEmpty) {
      return;
    }
    await _openExternalUrl(notification.itemUrl);
  }

  void _logout() {
    context.read<AuthService>().logout();
    context.go('/login');
  }

  void _showNotificationsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NotifDesignTokens.structRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: SafeArea(
            child: Consumer<NotificationService>(
              builder: (context, notificationService, _) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NotifDesignTokens.spaceLg,
                        NotifDesignTokens.spaceLg,
                        NotifDesignTokens.spaceLg,
                        NotifDesignTokens.spaceBase,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Notifications', style: _labelStyle),
                                SizedBox(height: NotifDesignTokens.spaceXs),
                                Text('Full feed', style: _sheetTitleStyle),
                              ],
                            ),
                          ),
                          if (notificationService.unreadCount > 0)
                            TextButton(
                              onPressed: notificationService.markingAllRead
                                  ? null
                                  : () => notificationService.markAllRead(),
                              child: Text(
                                notificationService.markingAllRead
                                    ? 'Working...'
                                    : 'Mark all read',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: notificationService.notifications.isEmpty
                          ? const Center(
                              child: _EmptyState(
                                icon: Icons.notifications_off_outlined,
                                title: 'No notifications yet',
                                message:
                                    'Scrapes that find new updates will show up here.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(
                                NotifDesignTokens.spaceLg,
                              ),
                              itemCount:
                                  notificationService.notifications.length,
                              separatorBuilder: (_, _) => const SizedBox(
                                height: NotifDesignTokens.spaceSm,
                              ),
                              itemBuilder: (context, index) {
                                final item =
                                    notificationService.notifications[index];
                                return _NotificationCard(
                                  notification: item,
                                  compact: false,
                                  isBusy: notificationService.isMarkingRead(
                                    item.id,
                                  ),
                                  onTap: () => _handleNotificationTap(item),
                                  onMarkRead: item.isUnread
                                      ? () => notificationService.markRead(
                                          item.id,
                                        )
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String? message) {
    if (!mounted || message == null || message.trim().isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = context.watch<AppSettingsController?>();
    final userData = context.watch<UserDataService>().userData;
    final linkService = context.watch<LinkService>();
    final notificationService = context.watch<NotificationService>();
    final unreadNotifications = notificationService.notifications
        .where((item) => item.isUnread)
        .take(6)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: NotifDesignTokens.structBg,
      appBar: AppBar(
        backgroundColor: NotifDesignTokens.structSurface,
        foregroundColor: NotifDesignTokens.structText,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: NotifDesignTokens.spaceLg,
        title: const Text('Home', style: _headlineStyle),
        leading: IconButton(
          tooltip: 'Log out',
          icon: const Icon(Icons.logout_sharp),
          onPressed: _logout,
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_sharp),
                onPressed: _showNotificationsSheet,
              ),
              if (notificationService.unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: FeedbackColors.error,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Text(
                      '${notificationService.unreadCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline_sharp),
            onPressed: () => context.push('/about'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_sharp),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: NotifDesignTokens.structBorder),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: linkService.creating ? null : _handleAddLink,
        backgroundColor: NotifDesignTokens.accentPrimary,
        foregroundColor: NotifDesignTokens.accentOnAccent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: linkService.creating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: NotifDesignTokens.accentOnAccent,
                ),
              )
            : const Icon(Icons.add_sharp),
      ),
      body: Stack(
        children: [
          if (appSettings?.designDitheringEnabled ?? true)
            const DitherOverlay(),
          RefreshIndicator(
            color: NotifDesignTokens.accentPrimary,
            onRefresh: _refreshDashboard,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 980;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    NotifDesignTokens.spaceLg,
                    NotifDesignTokens.spaceLg,
                    NotifDesignTokens.spaceLg,
                    96,
                  ),
                  children: [
                    _HeroPanel(
                      userData: userData,
                      linkCount: linkService.links.length,
                      unreadCount: notificationService.unreadCount,
                      backendLabel: _backendModeLabel(appSettings),
                      scrapeInProgress: linkService.scrapingAll,
                      onAddLink: linkService.creating ? null : _handleAddLink,
                      onScrapeAll: linkService.scrapingAll
                          ? null
                          : _handleScrapeAll,
                    ),
                    if (linkService.error != null) ...[
                      const SizedBox(height: NotifDesignTokens.spaceLg),
                      _ErrorBanner(message: linkService.error!),
                    ],
                    if (notificationService.error != null) ...[
                      const SizedBox(height: NotifDesignTokens.spaceLg),
                      _ErrorBanner(message: notificationService.error!),
                    ],
                    const SizedBox(height: NotifDesignTokens.spaceLg),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildLinksPanel(linkService),
                          ),
                          const SizedBox(width: NotifDesignTokens.spaceLg),
                          Expanded(
                            flex: 5,
                            child: _buildNotificationsPanel(
                              notificationService,
                              unreadNotifications,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildLinksPanel(linkService),
                      const SizedBox(height: NotifDesignTokens.spaceLg),
                      _buildNotificationsPanel(
                        notificationService,
                        unreadNotifications,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinksPanel(LinkService linkService) {
    return _DashboardPanel(
      label: 'Registry',
      title: 'Monitored links',
      badge: '${linkService.links.length}',
      loading: linkService.loading,
      action: TextButton.icon(
        onPressed: linkService.loading ? null : _refreshDashboard,
        icon: const Icon(Icons.sync_sharp, size: 16),
        label: const Text('Refresh'),
      ),
      child: linkService.loading && linkService.links.isEmpty
          ? const _LoadingState(message: 'Loading links...')
          : linkService.links.isEmpty
          ? const _EmptyState(
              icon: Icons.link_off_sharp,
              title: 'No links in the registry',
              message: 'Add a monitored page to start scraping for updates.',
            )
          : Column(
              children: [
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
                    const SizedBox(height: NotifDesignTokens.spaceSm),
                ],
              ],
            ),
    );
  }

  Widget _buildNotificationsPanel(
    NotificationService notificationService,
    List<NotificationItem> unreadNotifications,
  ) {
    return _DashboardPanel(
      label: 'Signal Feed',
      title: 'Unread notifications',
      badge: '${notificationService.unreadCount}',
      loading: notificationService.loading,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notificationService.unreadCount > 0)
            TextButton(
              onPressed: notificationService.markingAllRead
                  ? null
                  : () => notificationService.markAllRead(),
              child: Text(
                notificationService.markingAllRead
                    ? 'Working...'
                    : 'Mark all read',
              ),
            ),
          TextButton(
            onPressed: _showNotificationsSheet,
            child: const Text('Open feed'),
          ),
        ],
      ),
      child:
          notificationService.loading &&
              notificationService.notifications.isEmpty
          ? const _LoadingState(message: 'Loading notifications...')
          : unreadNotifications.isEmpty
          ? const _EmptyState(
              icon: Icons.mark_email_read_outlined,
              title: 'Inbox clear',
              message:
                  'Unread notifications will appear here after new updates are found.',
            )
          : Column(
              children: [
                for (final item in unreadNotifications) ...[
                  _NotificationCard(
                    notification: item,
                    isBusy: notificationService.isMarkingRead(item.id),
                    onTap: () => _handleNotificationTap(item),
                    onMarkRead: () => notificationService.markRead(item.id),
                  ),
                  if (item != unreadNotifications.last)
                    const SizedBox(height: NotifDesignTokens.spaceSm),
                ],
              ],
            ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.userData,
    required this.linkCount,
    required this.unreadCount,
    required this.backendLabel,
    required this.scrapeInProgress,
    required this.onAddLink,
    required this.onScrapeAll,
  });

  final UserData? userData;
  final int linkCount;
  final int unreadCount;
  final String backendLabel;
  final bool scrapeInProgress;
  final VoidCallback? onAddLink;
  final VoidCallback? onScrapeAll;

  @override
  Widget build(BuildContext context) {
    final name = userData?.name.trim();
    final username = userData?.username.trim();
    final identity = name != null && name.isNotEmpty
        ? name
        : username != null && username.isNotEmpty
        ? username
        : 'operator';

    return Container(
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      padding: const EdgeInsets.all(NotifDesignTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monitoring Desk', style: _labelStyle),
          const SizedBox(height: NotifDesignTokens.spaceSm),
          const Text('Quiet control of a noisy feed.', style: _displayStyle),
          const SizedBox(height: NotifDesignTokens.spaceBase),
          Text(
            'Signed in as $identity. Keep the registry deliberate, run scrapes when you need fresh signals, and let the feed stay readable.',
            style: _bodyStyle.copyWith(color: NotifDesignTokens.structText2),
          ),
          const SizedBox(height: NotifDesignTokens.spaceLg),
          Wrap(
            spacing: NotifDesignTokens.spaceSm,
            runSpacing: NotifDesignTokens.spaceSm,
            children: [
              _MetricPlate(label: 'Links', value: '$linkCount'),
              _MetricPlate(label: 'Unread', value: '$unreadCount'),
              _MetricPlate(label: 'Backend', value: backendLabel),
            ],
          ),
          const SizedBox(height: NotifDesignTokens.spaceLg),
          Wrap(
            spacing: NotifDesignTokens.spaceSm,
            runSpacing: NotifDesignTokens.spaceSm,
            children: [
              FilledButton.icon(
                style: NotifDesignTokens.framedButtonStyle(isPrimary: true),
                onPressed: onScrapeAll,
                icon: scrapeInProgress
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NotifDesignTokens.accentOnAccent,
                        ),
                      )
                    : const Icon(Icons.radar_sharp, size: 16),
                label: Text(scrapeInProgress ? 'SCRAPING' : 'SCRAPE ALL'),
              ),
              OutlinedButton.icon(
                style: NotifDesignTokens.framedButtonStyle(isPrimary: false),
                onPressed: onAddLink,
                icon: const Icon(Icons.add_sharp, size: 16),
                label: const Text('ADD LINK'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.label,
    required this.title,
    required this.child,
    this.badge,
    this.action,
    this.loading = false,
  });

  final String label;
  final String title;
  final String? badge;
  final Widget child;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      child: Column(
        children: [
          if (loading)
            const LinearProgressIndicator(
              minHeight: 1,
              backgroundColor: NotifDesignTokens.structDivider,
              color: NotifDesignTokens.accentPrimary,
            ),
          Padding(
            padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
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
                          Text(label, style: _labelStyle),
                          const SizedBox(height: NotifDesignTokens.spaceXs),
                          Row(
                            children: [
                              Expanded(
                                child: Text(title, style: _panelTitleStyle),
                              ),
                              if (badge != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: NotifDesignTokens.spaceSm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: NotifDesignTokens.accentDim,
                                    border: Border.all(
                                      color: NotifDesignTokens.accentMuted,
                                    ),
                                  ),
                                  child: Text(
                                    badge!,
                                    style: _monoStyle.copyWith(
                                      color: NotifDesignTokens.accentText,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(width: NotifDesignTokens.spaceSm),
                      action!,
                    ],
                  ],
                ),
                const SizedBox(height: NotifDesignTokens.spaceBase),
                child,
              ],
            ),
          ),
        ],
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
    final busy = isScraping || isSaving || isDeleting;

    return Container(
      decoration: BoxDecoration(
        color: NotifDesignTokens.structRaised,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
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
                    Text(link.name, style: _itemTitleStyle),
                    const SizedBox(height: NotifDesignTokens.spaceXs),
                    Text(
                      link.url,
                      style: _monoStyle.copyWith(
                        color: NotifDesignTokens.structText3,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: NotifDesignTokens.spaceSm),
                    Wrap(
                      spacing: NotifDesignTokens.spaceSm,
                      runSpacing: NotifDesignTokens.spaceSm,
                      children: [
                        _TagChip(label: link.strategyLabel),
                        _TagChip(
                          label: link.lastScraped == null
                              ? 'Never scraped'
                              : 'Last scrape ${_formatTimeAgo(link.lastScraped!)}',
                        ),
                      ],
                    ),
                    if (link.selectors.isNotEmpty) ...[
                      const SizedBox(height: NotifDesignTokens.spaceSm),
                      Text(
                        'Selectors: ${link.selectors.join(', ')}',
                        style: _bodyStyle.copyWith(
                          color: NotifDesignTokens.structText2,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NotifDesignTokens.accentPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: NotifDesignTokens.spaceBase),
          Wrap(
            spacing: NotifDesignTokens.spaceSm,
            runSpacing: NotifDesignTokens.spaceSm,
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    this.onMarkRead,
    this.isBusy = false,
    this.compact = true,
  });

  final NotificationItem notification;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;
  final bool isBusy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isBusy ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: NotifDesignTokens.structRaised,
          border: Border.all(
            color: notification.isUnread
                ? NotifDesignTokens.accentMuted
                : NotifDesignTokens.structBorder,
          ),
        ),
        padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: notification.isUnread
                    ? NotifDesignTokens.accentPrimary
                    : NotifDesignTokens.structText3,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: NotifDesignTokens.spaceBase),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title, style: _itemTitleStyle),
                  if (notification.description.isNotEmpty) ...[
                    const SizedBox(height: NotifDesignTokens.spaceXs),
                    Text(
                      notification.description,
                      maxLines: compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle.copyWith(
                        color: NotifDesignTokens.structText2,
                      ),
                    ),
                  ],
                  const SizedBox(height: NotifDesignTokens.spaceSm),
                  Text(
                    _formatTimestamp(notification.createdAt),
                    style: _monoStyle.copyWith(
                      color: NotifDesignTokens.structText3,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isBusy)
              const Padding(
                padding: EdgeInsets.only(left: NotifDesignTokens.spaceSm),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NotifDesignTokens.accentPrimary,
                  ),
                ),
              )
            else if (onMarkRead != null)
              TextButton(onPressed: onMarkRead, child: const Text('Read')),
          ],
        ),
      ),
    );
  }
}

class _MetricPlate extends StatelessWidget {
  const _MetricPlate({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
      decoration: BoxDecoration(
        color: NotifDesignTokens.structRaised,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _labelStyle),
          const SizedBox(height: NotifDesignTokens.spaceXs),
          Text(value, style: _metricStyle),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NotifDesignTokens.spaceSm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      child: Text(
        label,
        style: _monoStyle.copyWith(
          color: NotifDesignTokens.structText2,
          fontSize: 11,
        ),
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
    final foreground = destructive
        ? FeedbackColors.error
        : NotifDesignTokens.accentText;

    return OutlinedButton.icon(
      style: NotifDesignTokens.framedButtonStyle(isPrimary: false).copyWith(
        foregroundColor: WidgetStatePropertyAll(foreground),
        side: WidgetStateProperty.resolveWith((states) {
          if (destructive) {
            return BorderSide(
              color: states.contains(WidgetState.hovered)
                  ? FeedbackColors.error
                  : FeedbackColors.error.withValues(alpha: 0.45),
            );
          }
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(
              color: NotifDesignTokens.accentDim,
              width: NotifDesignTokens.borderFocusWidth,
            );
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return const BorderSide(color: NotifDesignTokens.accentMuted);
          }
          return const BorderSide(color: NotifDesignTokens.structBorder);
        }),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label.toUpperCase()),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NotifDesignTokens.spaceXl),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: NotifDesignTokens.accentPrimary,
            ),
          ),
          const SizedBox(height: NotifDesignTokens.spaceBase),
          Text(
            message,
            style: _bodyStyle.copyWith(color: NotifDesignTokens.structText2),
          ),
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
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NotifDesignTokens.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: NotifDesignTokens.structText3),
          const SizedBox(height: NotifDesignTokens.spaceBase),
          Text(title, style: _panelTitleStyle),
          const SizedBox(height: NotifDesignTokens.spaceSm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: _bodyStyle.copyWith(color: NotifDesignTokens.structText2),
            ),
          ),
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
    return Container(
      padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
      decoration: BoxDecoration(
        color: FeedbackColors.error.withValues(alpha: 0.12),
        border: Border.all(color: FeedbackColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline_sharp,
              color: FeedbackColors.error,
              size: 18,
            ),
          ),
          const SizedBox(width: NotifDesignTokens.spaceSm),
          Expanded(
            child: Text(
              message,
              style: _bodyStyle.copyWith(color: FeedbackColors.error),
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
                    label: 'Name',
                    hint: 'Threadmarks, release feed, changelog...',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Give the link a name.'
                      : null,
                ),
                const SizedBox(height: NotifDesignTokens.spaceBase),
                TextFormField(
                  controller: _urlController,
                  decoration: _dialogInputDecoration(
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
                const SizedBox(height: NotifDesignTokens.spaceBase),
                DropdownButtonFormField<String>(
                  initialValue: _selectedStrategy,
                  decoration: _dialogInputDecoration(label: 'Strategy'),
                  items: _availableStrategies
                      .map(
                        (choice) => DropdownMenuItem<String>(
                          value: choice,
                          child: Text(formatStrategyClassName(choice)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedStrategy = value;
                      if (_selectedStrategy != generalSelectorStrategy &&
                          _selectorsController.text.trim().isEmpty) {
                        _selectorsController.text = 'body';
                      }
                    });
                  },
                ),
                const SizedBox(height: NotifDesignTokens.spaceSm),
                Text(
                  _strategyDescription(_selectedStrategy),
                  style: _bodyStyle.copyWith(
                    color: NotifDesignTokens.structText3,
                    fontSize: 13,
                  ),
                ),
                if (_selectedStrategy == generalSelectorStrategy) ...[
                  const SizedBox(height: NotifDesignTokens.spaceBase),
                  TextFormField(
                    controller: _selectorsController,
                    maxLines: 4,
                    decoration: _dialogInputDecoration(
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
        FilledButton(
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }

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

InputDecoration _dialogInputDecoration({required String label, String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: NotifDesignTokens.structText2),
    hintStyle: const TextStyle(color: NotifDesignTokens.structText3),
    filled: true,
    fillColor: NotifDesignTokens.structSurface,
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: NotifDesignTokens.structBorder),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(
        color: NotifDesignTokens.accentDim,
        width: NotifDesignTokens.borderFocusWidth,
      ),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: FeedbackColors.error),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: FeedbackColors.error, width: 2),
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

String _formatTimeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) {
    return 'just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

String _formatTimestamp(DateTime dateTime) {
  final twoDigitMinute = dateTime.minute.toString().padLeft(2, '0');
  final twoDigitHour = dateTime.hour.toString().padLeft(2, '0');
  return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
      '$twoDigitHour:$twoDigitMinute';
}

const TextStyle _headlineStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  color: NotifDesignTokens.structText,
  fontSize: 28,
);

const TextStyle _displayStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  color: NotifDesignTokens.structText,
  fontSize: 38,
  height: 1.02,
);

const TextStyle _sheetTitleStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  color: NotifDesignTokens.structText,
  fontSize: 22,
);

const TextStyle _panelTitleStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  color: NotifDesignTokens.structText,
  fontSize: 24,
);

const TextStyle _itemTitleStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  color: NotifDesignTokens.structText,
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

const TextStyle _metricStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  color: NotifDesignTokens.structText,
  fontSize: 28,
);

const TextStyle _bodyStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  color: NotifDesignTokens.structText,
  fontSize: 14,
  height: 1.45,
);

const TextStyle _labelStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  color: NotifDesignTokens.structText3,
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.2,
);

const TextStyle _monoStyle = TextStyle(
  fontFamily: NotifDesignTokens.monoFont,
  color: NotifDesignTokens.structText,
  fontSize: 12,
  height: 1.3,
);
