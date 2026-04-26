import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
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

    _showMessage(success ? 'Link added to the registry.' : linkService.error);
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
        title: 'Edit link',
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

    _showMessage(success ? 'Link updated.' : linkService.error);
  }

  Future<void> _handleDeleteLink(Link link) async {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
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

    _showMessage(success ? 'Link removed.' : linkService.error);
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

    if (await launchUrl(uri)) return;

    if (!mounted) return;
    _showMessage('Could not open $url');
  }

  Future<void> _handleNotificationTap(NotificationItem notification) async {
    final notificationService = context.read<NotificationService>();
    if (notification.isUnread) {
      await notificationService.markRead(notification.id);
    }
    if (!mounted || notification.itemUrl.isEmpty) return;
    await _openExternalUrl(notification.itemUrl);
  }

  void _logout() {
    context.read<AuthService>().logout();
    context.go('/login');
  }

  void _showNotificationsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final tokens = NotifTokens.of(sheetContext);
        final text$ = NotifTextTheme.of(sheetContext);

        return FractionallySizedBox(
          heightFactor: 0.88,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.bg1,
                border: Border(top: BorderSide(color: tokens.ruleStrong)),
              ),
              child: Consumer<NotificationService>(
                builder: (context, notificationService, _) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Eyebrow(
                                    'Notifications',
                                    tone: EyebrowTone.accent,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Full feed',
                                    style: text$.title.copyWith(
                                      color: tokens.ink,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (notificationService.unreadCount > 0)
                              NotifButton(
                                label: notificationService.markingAllRead
                                    ? 'Working'
                                    : 'Mark all read',
                                variant: NotifButtonVariant.ghost,
                                size: NotifButtonSize.sm,
                                onPressed: notificationService.markingAllRead
                                    ? null
                                    : () => notificationService.markAllRead(),
                              ),
                          ],
                        ),
                      ),
                      Rule(strength: RuleStrength.faint),
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
                                padding: const EdgeInsets.all(24),
                                itemCount:
                                    notificationService.notifications.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
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
          ),
        );
      },
    );
  }

  void _showMessage(String? message) {
    if (!mounted || message == null || message.trim().isEmpty) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final appSettings = context.watch<AppSettingsController?>();
    final userData = context.watch<UserDataService>().userData;
    final linkService = context.watch<LinkService>();
    final notificationService = context.watch<NotificationService>();
    final unreadNotifications = notificationService.notifications
        .where((item) => item.isUnread)
        .take(6)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: tokens.bg0,
      appBar: AppBar(
        backgroundColor: tokens.bg0,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Log out',
          icon: Icon(Icons.logout_sharp, color: tokens.inkDim),
          onPressed: _logout,
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
            Text('/ desk', style: text$.micro.copyWith(color: tokens.inkMute)),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                tooltip: 'Notifications',
                icon: Icon(Icons.notifications_sharp, color: tokens.inkDim),
                onPressed: _showNotificationsSheet,
              ),
              if (notificationService.unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _Badge(value: '${notificationService.unreadCount}'),
                ),
            ],
          ),
          IconButton(
            tooltip: 'About',
            icon: Icon(Icons.info_outline_sharp, color: tokens.inkDim),
            onPressed: () => context.push('/about'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Icon(Icons.settings_sharp, color: tokens.inkDim),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tokens.rule),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: linkService.creating ? null : _handleAddLink,
        backgroundColor: tokens.btnBg,
        foregroundColor: tokens.btnInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: linkService.creating
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.btnInk,
                ),
              )
            : const Icon(Icons.add_sharp),
      ),
      body: Stack(
        children: [
          if (appSettings?.designDitheringEnabled ?? true)
            const DitherOverlay(),
          RefreshIndicator(
            color: tokens.accent,
            backgroundColor: tokens.bg2,
            onRefresh: _refreshDashboard,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 980;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
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
                      const SizedBox(height: 18),
                      _ErrorBanner(message: linkService.error!),
                    ],
                    if (notificationService.error != null) ...[
                      const SizedBox(height: 18),
                      _ErrorBanner(message: notificationService.error!),
                    ],
                    const SizedBox(height: 24),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildLinksPanel(linkService),
                          ),
                          const SizedBox(width: 24),
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
                      const SizedBox(height: 24),
                      _buildNotificationsPanel(
                        notificationService,
                        unreadNotifications,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _HomeFooter(userData: userData),
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
      index: 1,
      label: 'Registry',
      title: 'Monitored links',
      meta: '${linkService.links.length} total',
      loading: linkService.loading,
      action: NotifButton(
        label: 'Refresh',
        icon: Icons.sync_sharp,
        variant: NotifButtonVariant.link,
        size: NotifButtonSize.sm,
        onPressed: linkService.loading ? null : _refreshDashboard,
      ),
      child: linkService.loading && linkService.links.isEmpty
          ? const _LoadingState(message: 'Loading links...')
          : linkService.links.isEmpty
          ? _EmptyState(
              icon: Icons.link_off_sharp,
              title: 'No links in the registry',
              message: 'Add a monitored page to start scraping for updates.',
              action: NotifButton(
                label: 'Add link',
                icon: Icons.add_sharp,
                onPressed: linkService.creating ? null : _handleAddLink,
              ),
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
                    const SizedBox(height: 12),
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
      index: 2,
      label: 'Signal feed',
      title: 'Unread notifications',
      meta: '${notificationService.unreadCount} unread',
      loading: notificationService.loading,
      action: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (notificationService.unreadCount > 0)
            NotifButton(
              label: notificationService.markingAllRead ? 'Working' : 'Read all',
              variant: NotifButtonVariant.link,
              size: NotifButtonSize.sm,
              onPressed: notificationService.markingAllRead
                  ? null
                  : () => notificationService.markAllRead(),
            ),
          NotifButton(
            label: 'Open feed',
            variant: NotifButtonVariant.link,
            size: NotifButtonSize.sm,
            onPressed: _showNotificationsSheet,
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
                    const SizedBox(height: 12),
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
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final name = userData?.name.trim();
    final username = userData?.username.trim();
    final identity = name != null && name.isNotEmpty
        ? name
        : username != null && username.isNotEmpty
        ? username
        : 'operator';

    return NotifCard(
      cornerMarks: true,
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Monitoring desk', tone: EyebrowTone.accent),
              const SizedBox(height: 10),
              Text(
                'Quiet control of a noisy feed.',
                style: text$.display.copyWith(
                  color: tokens.ink,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Signed in as $identity. Keep the registry deliberate, run scrapes when you need fresh signals, and let the feed stay readable.',
                style: text$.bodyLong.copyWith(color: tokens.inkDim),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricPlate(label: 'Links', value: '$linkCount'),
                  _MetricPlate(label: 'Unread', value: '$unreadCount'),
                  _MetricPlate(label: 'Backend', value: backendLabel),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  NotifButton(
                    label: scrapeInProgress ? 'Scraping' : 'Scrape all',
                    icon: Icons.radar_sharp,
                    onPressed: onScrapeAll,
                  ),
                  NotifButton(
                    label: 'Add link',
                    icon: Icons.add_sharp,
                    variant: NotifButtonVariant.ghost,
                    onPressed: onAddLink,
                  ),
                ],
              ),
            ],
          );

          if (!isWide) return copy;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: copy),
              const SizedBox(width: 28),
              Expanded(
                flex: 2,
                child: Opacity(
                  opacity: 0.82,
                  child: _SignalOrb(size: math.min(220, constraints.maxWidth / 4)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.index,
    required this.label,
    required this.title,
    required this.child,
    this.meta,
    this.action,
    this.loading = false,
  });

  final int index;
  final String label;
  final String title;
  final String? meta;
  final Widget child;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IndexRule(index: index, title: label, meta: meta),
        NotifCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading)
                LinearProgressIndicator(
                  minHeight: 1,
                  backgroundColor: tokens.rule,
                  color: tokens.accent,
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: text$.title.copyWith(
                              color: tokens.ink,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 12),
                          action!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    child,
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return NotifCard(
      padding: EdgeInsets.zero,
      onTap: isBusy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: StatusDot(
                state: notification.isUnread
                    ? StatusDotState.live
                    : StatusDotState.idle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: text$.heading.copyWith(color: tokens.ink),
                  ),
                  if (notification.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notification.description,
                      maxLines: compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _formatTimestamp(notification.createdAt),
                    style: text$.micro.copyWith(color: tokens.inkMute),
                  ),
                ],
              ),
            ),
            if (isBusy)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
              )
            else if (onMarkRead != null)
              NotifButton(
                label: 'Read',
                variant: NotifButtonVariant.link,
                size: NotifButtonSize.sm,
                onPressed: onMarkRead,
              ),
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
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bg1,
        border: Border.all(color: tokens.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label, size: EyebrowSize.micro),
          const SizedBox(height: 6),
          Text(value, style: text$.heading.copyWith(color: tokens.ink)),
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
            child: Text(
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

class _HomeFooter extends StatelessWidget {
  const _HomeFooter({required this.userData});

  final UserData? userData;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.rule)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text(
                  (userData == null
                          ? 'profile loading'
                          : '@${userData!.username}')
                      .toUpperCase(),
                  style: text$.eyebrow.copyWith(color: tokens.inkDim),
                ),
                if (!isNarrow)
                  Text(
                    'sources active'.toUpperCase(),
                    style: text$.eyebrow.copyWith(color: tokens.inkMute),
                  ),
              ],
            ),
          ),
          StatusDot(
            state: userData == null
                ? StatusDotState.idle
                : StatusDotState.synced,
            label: userData == null ? 'loading' : 'authenticated',
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.accent,
        border: Border.all(color: tokens.bg0),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: text$.micro.copyWith(color: tokens.bg0),
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

String _formatTimeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

String _formatTimestamp(DateTime dateTime) {
  final twoDigitMinute = dateTime.minute.toString().padLeft(2, '0');
  final twoDigitHour = dateTime.hour.toString().padLeft(2, '0');
  return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
      '$twoDigitHour:$twoDigitMinute';
}
