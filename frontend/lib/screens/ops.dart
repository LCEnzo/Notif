import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/ops.dart';
import 'package:provider/provider.dart';

class OpsPage extends StatefulWidget {
  const OpsPage({super.key});

  @override
  State<OpsPage> createState() => _OpsPageState();
}

class _OpsPageState extends State<OpsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<UserDataService>().userData;
      if (user?.isStaff == true || user?.isSuperuser == true) {
        context.read<OpsService>().fetchEvents();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final settings = context.watch<AppSettingsController?>();
    final user = context.watch<UserDataService>().userData;
    final ops = context.watch<OpsService>();
    final hasOpsAccess = user?.isStaff == true || user?.isSuperuser == true;

    return Scaffold(
      backgroundColor: tokens.bg1,
      appBar: AppBar(
        backgroundColor: tokens.bg1,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 24,
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
            Text('/ ops', style: text$.micro.copyWith(color: tokens.inkMute)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: NotifButton(
              label: 'Home',
              icon: Icons.arrow_back,
              variant: NotifButtonVariant.ghost,
              size: NotifButtonSize.sm,
              onPressed: () => context.go('/home'),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tokens.rule),
        ),
      ),
      body: Stack(
        children: [
          if (settings?.designDitheringEnabled ?? true) const DitherOverlay(),
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: hasOpsAccess
                    ? _OpsBody(ops: ops)
                    : _AccessDenied(text$: text$, tokens: tokens),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpsBody extends StatelessWidget {
  const _OpsBody({required this.ops});

  final OpsService ops;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Staff only', tone: EyebrowTone.accent),
        const SizedBox(height: 8),
        Text('Operations', style: text$.title.copyWith(color: tokens.ink)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            NotifButton(
              label: ops.loading ? 'Refreshing' : 'Refresh events',
              icon: Icons.refresh,
              onPressed: ops.loading ? null : ops.fetchEvents,
            ),
            NotifButton(
              label: ops.downloading ? 'Preparing backup' : 'Download DB',
              icon: Icons.download,
              variant: NotifButtonVariant.ghost,
              onPressed: ops.downloading ? null : ops.downloadSqliteBackup,
            ),
          ],
        ),
        if (ops.error != null) ...[
          const SizedBox(height: 16),
          Text(
            ops.error!,
            style: text$.body.copyWith(color: NotifFeedback.error),
          ),
        ],
        const SizedBox(height: 32),
        const IndexRule(index: 1, title: 'Recent events'),
        if (ops.loading && ops.events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Loading events...',
              style: text$.body.copyWith(color: tokens.inkDim),
            ),
          )
        else if (ops.events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No system events recorded yet.',
              style: text$.body.copyWith(color: tokens.inkDim),
            ),
          )
        else
          Column(
            children: [for (final event in ops.events) _EventRow(event: event)],
          ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final SystemEvent event;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final levelColor = switch (event.level) {
      'critical' || 'error' => NotifFeedback.error,
      'warning' => NotifFeedback.warning,
      _ => tokens.accent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.rule, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _formatTimestamp(event.createdAt),
                style: text$.code.copyWith(color: tokens.inkMute),
              ),
              Text(
                event.level.toUpperCase(),
                style: text$.micro.copyWith(color: levelColor),
              ),
              Text(
                event.source,
                style: text$.micro.copyWith(color: tokens.inkDim),
              ),
              Text(
                event.kind,
                style: text$.micro.copyWith(color: tokens.inkMute),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(event.message, style: text$.body.copyWith(color: tokens.ink)),
          if (event.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(event.details),
              style: text$.code.copyWith(color: tokens.inkDim),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.text$, required this.tokens});

  final NotifTextTheme text$;
  final NotifTokens tokens;

  @override
  Widget build(BuildContext context) {
    return NotifCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Restricted', tone: EyebrowTone.accent),
          const SizedBox(height: 8),
          Text(
            'Operations access requires a staff account.',
            style: text$.body.copyWith(color: tokens.ink),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  final ss = value.second.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm:$ss';
}
