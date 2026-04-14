import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/notif_design_tokens.dart';
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
    // Fetch data on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LinkService>().fetchLinks();
      context.read<NotificationService>().fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final linkService = context.watch<LinkService>();
    final notifService = context.watch<NotificationService>();

    return Scaffold(
      backgroundColor: NotifDesignTokens.structBg,
      appBar: _buildAppBar(authService, notifService),
      body: RefreshIndicator(
        color: NotifDesignTokens.accentPrimary,
        onRefresh: () async {
          await Future.wait([
            linkService.fetchLinks(),
            notifService.fetchNotifications(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            // Scrape all button
            SliverToBoxAdapter(child: _buildScrapeBar(linkService)),

            // Error banner
            if (linkService.error != null)
              SliverToBoxAdapter(child: _buildErrorBanner(linkService.error!)),

            // Links section
            _buildLinksSection(linkService),

            // Notifications section
            _buildNotificationsSection(notifService),

            // Bottom padding
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NotifDesignTokens.accentPrimary,
        foregroundColor: NotifDesignTokens.accentOnAccent,
        onPressed: () => _showAddLinkDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(
    AuthService authService,
    NotificationService notifService,
  ) {
    return AppBar(
      backgroundColor: NotifDesignTokens.structSurface,
      foregroundColor: NotifDesignTokens.structText,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(
        'Notif',
        style: TextStyle(
          fontFamily: NotifDesignTokens.displayFont,
          fontSize: 24,
          color: NotifDesignTokens.structText,
        ),
      ),
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Logout',
        onPressed: () {
          authService.logout();
          context.go('/login');
        },
      ),
      actions: [
        // Notification badge
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () => _showNotificationsSheet(context, notifService),
            ),
            if (notifService.unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: FeedbackColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${notifService.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Scrape bar
  // ---------------------------------------------------------------------------

  Widget _buildScrapeBar(LinkService linkService) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: NotifDesignTokens.accentPrimary,
            foregroundColor: NotifDesignTokens.accentOnAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NotifDesignTokens.radiusSm),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: linkService.links.isEmpty
              ? null
              : () async {
                  final result = await linkService.triggerScrape();
                  if (!mounted) return;
                  final status = result['status'];
                  if (status == 'ok' || status == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Scrape complete')),
                    );
                    context.read<NotificationService>().fetchNotifications();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result['message'] ?? 'Scrape failed'),
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text(
            'Scrape all links',
            style: TextStyle(
              fontFamily: NotifDesignTokens.bodyFont,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error banner
  // ---------------------------------------------------------------------------

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FeedbackColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NotifDesignTokens.radiusSm),
        border: Border.all(
          color: FeedbackColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: FeedbackColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: FeedbackColors.error,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Links section
  // ---------------------------------------------------------------------------

  Widget _buildLinksSection(LinkService linkService) {
    if (linkService.loading && linkService.links.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(
            color: NotifDesignTokens.accentPrimary,
          ),
        ),
      );
    }

    if (linkService.links.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildLinkCard(linkService.links[index]),
          childCount: linkService.links.length,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off,
              size: 48,
              color: NotifDesignTokens.structText3,
            ),
            const SizedBox(height: 16),
            Text(
              'No links yet',
              style: TextStyle(
                fontFamily: NotifDesignTokens.bodyFont,
                fontSize: 18,
                color: NotifDesignTokens.structText2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add a link to monitor',
              style: TextStyle(
                fontSize: 14,
                color: NotifDesignTokens.structText3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCard(Link link) {
    final timeAgo = link.lastScraped != null
        ? _formatTimeAgo(link.lastScraped!)
        : 'Never scraped';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        borderRadius: BorderRadius.circular(NotifDesignTokens.radiusSm),
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          link.name,
          style: const TextStyle(
            fontFamily: NotifDesignTokens.bodyFont,
            fontWeight: FontWeight.w600,
            color: NotifDesignTokens.structText,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            link.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NotifDesignTokens.structText3,
              fontSize: 12,
            ),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              timeAgo,
              style: TextStyle(
                fontSize: 11,
                color: link.lastScraped != null
                    ? NotifDesignTokens.structText3
                    : FeedbackColors.warning,
              ),
            ),
            if (link.strategy.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  link.strategy,
                  style: const TextStyle(
                    fontSize: 10,
                    color: NotifDesignTokens.accentText,
                    fontFamily: NotifDesignTokens.monoFont,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Notifications section
  // ---------------------------------------------------------------------------

  Widget _buildNotificationsSection(NotificationService notifService) {
    final unread =
        notifService.notifications.where((n) => n.status == 'unread').toList();

    if (unread.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  'Updates',
                  style: TextStyle(
                    fontFamily: NotifDesignTokens.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: NotifDesignTokens.structText2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NotifDesignTokens.accentDim,
                    borderRadius:
                        BorderRadius.circular(NotifDesignTokens.radiusSm),
                  ),
                  child: Text(
                    '${unread.length}',
                    style: const TextStyle(
                      color: NotifDesignTokens.accentText,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => notifService.markAllRead(),
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(
                      color: NotifDesignTokens.accentText,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...unread.take(5).map((n) => _buildNotificationTile(n, notifService)),
        ]),
      ),
    );
  }

  Widget _buildNotificationTile(
    NotificationItem notification,
    NotificationService notifService,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: NotifDesignTokens.structRaised,
        borderRadius: BorderRadius.circular(NotifDesignTokens.radiusSm),
        border: Border.all(
          color: NotifDesignTokens.accentDim.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: NotifDesignTokens.accentPrimary,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          notification.title,
          style: const TextStyle(
            color: NotifDesignTokens.structText,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: notification.description.isNotEmpty
            ? Text(
                notification.description,
                style: const TextStyle(
                  color: NotifDesignTokens.structText3,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        onTap: () => notifService.markRead(notification.id),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Add link dialog
  // ---------------------------------------------------------------------------

  void _showAddLinkDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NotifDesignTokens.structSurface,
        title: const Text(
          'Add link',
          style: TextStyle(
            fontFamily: NotifDesignTokens.bodyFont,
            color: NotifDesignTokens.structText,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                style: const TextStyle(color: NotifDesignTokens.structText),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle:
                      const TextStyle(color: NotifDesignTokens.structText3),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: NotifDesignTokens.structBorder),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide:
                        BorderSide(color: NotifDesignTokens.accentPrimary),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: urlController,
                style: const TextStyle(color: NotifDesignTokens.structText),
                decoration: InputDecoration(
                  labelText: 'URL',
                  labelStyle:
                      const TextStyle(color: NotifDesignTokens.structText3),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: NotifDesignTokens.structBorder),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide:
                        BorderSide(color: NotifDesignTokens.accentPrimary),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: NotifDesignTokens.structText3),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NotifDesignTokens.accentPrimary,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final linkService = context.read<LinkService>();
              final success = await linkService.createLink(
                nameController.text.trim(),
                urlController.text.trim(),
                'general_selector', // default strategy
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link added')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Notifications sheet
  // ---------------------------------------------------------------------------

  void _showNotificationsSheet(
    BuildContext context,
    NotificationService notifService,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NotifDesignTokens.structSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final all = notifService.notifications;
        if (all.isEmpty) {
          return const SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'No notifications yet',
                style: TextStyle(color: NotifDesignTokens.structText3),
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'All notifications',
                      style: TextStyle(
                        fontFamily: NotifDesignTokens.bodyFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: NotifDesignTokens.structText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        notifService.markAllRead();
                        Navigator.pop(sheetContext);
                      },
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(color: NotifDesignTokens.accentText),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: NotifDesignTokens.structDivider, height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: all.length,
                  itemBuilder: (context, index) {
                    final n = all[index];
                    final isRead = n.status != 'unread';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isRead
                            ? Icons.check_circle_outline
                            : Icons.circle_notifications,
                        color: isRead
                            ? NotifDesignTokens.structText3
                            : NotifDesignTokens.accentPrimary,
                        size: 20,
                      ),
                      title: Text(
                        n.title,
                        style: TextStyle(
                          color: NotifDesignTokens.structText,
                          fontSize: 13,
                          fontWeight:
                              isRead ? FontWeight.normal : FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: n.description.isNotEmpty
                          ? Text(
                              n.description,
                              style: const TextStyle(
                                color: NotifDesignTokens.structText3,
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () {
                        if (!isRead) notifService.markRead(n.id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}';
  }
}
