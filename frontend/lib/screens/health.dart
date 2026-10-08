import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/health/health_service.dart';
import 'package:notif/services/health/sync_store.dart';
import 'package:provider/provider.dart';

/// Health Connect export: access, coverage, backfill and sync state.
class HealthPage extends StatefulWidget {
  const HealthPage({
    super.key,
    this.pollInterval = const Duration(seconds: 5),
  });

  /// How often the screen re-reads what the WorkManager isolate wrote.
  final Duration pollInterval;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final health = context.read<HealthService>();
      unawaited(health.refresh());
      _poll = Timer.periodic(
        widget.pollInterval,
        (_) => unawaited(health.reloadSnapshot()),
      );
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final settings = context.watch<AppSettingsController?>();
    final health = context.watch<HealthService>();

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
            Text(
              '/ health',
              style: text$.micro.copyWith(color: tokens.inkMute),
            ),
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
                constraints: const BoxConstraints(maxWidth: 860),
                child: _HealthBody(health: health),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthBody extends StatelessWidget {
  const _HealthBody({required this.health});

  final HealthService health;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final snapshot = health.snapshot;
    final failure = health.actionFailure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Health Connect', tone: EyebrowTone.accent),
        const SizedBox(height: 8),
        Text('Health sync', style: text$.title.copyWith(color: tokens.ink)),
        const SizedBox(height: 16),
        if (snapshot.sessionExpired) ...[
          const _Banner(
            key: Key('health-session-expired'),
            text: 'Signed out; health sync is paused until the next sign-in.',
          ),
          const SizedBox(height: 16),
        ],
        if (failure != null) ...[
          _Banner(
            key: const Key('health-action-failure'),
            text: failure.message,
          ),
          const SizedBox(height: 16),
        ],
        const IndexRule(index: 0, title: 'Availability'),
        _Availability(health: health),
        if (health.status case final status? when status.available) ...[
          const SizedBox(height: 32),
          const IndexRule(index: 1, title: 'Access'),
          _Access(health: health),
          if (status.readableTypes.isNotEmpty) ...[
            const SizedBox(height: 32),
            const IndexRule(index: 2, title: 'Sync'),
            _Sync(health: health),
          ],
          if (status.anyDataReadable) ...[
            const SizedBox(height: 32),
            const IndexRule(index: 3, title: 'Coverage'),
            _Coverage(health: health),
          ],
          if (status.readableTypes.isNotEmpty) ...[
            const SizedBox(height: 32),
            const IndexRule(index: 4, title: 'Backfill'),
            _Backfill(health: health),
          ],
        ],
      ],
    );
  }
}

class _Availability extends StatelessWidget {
  const _Availability({required this.health});

  final HealthService health;

  @override
  Widget build(BuildContext context) {
    final (dot, text) = switch (health.availability) {
      HealthUnsupported() => (
        StatusDotState.idle,
        'Health Connect exists only on Android.',
      ),
      HealthChecking() => (StatusDotState.idle, 'Checking Health Connect.'),
      HealthCheckFailed(:final failure) => (
        StatusDotState.error,
        failure.message,
      ),
      HealthKnown(:final status) => switch (status.sdk) {
        HcSdkStatus.available => (
          StatusDotState.synced,
          'Health Connect is available.',
        ),
        HcSdkStatus.updateRequired => (
          StatusDotState.warning,
          'Health Connect needs an update from the Play Store.',
        ),
        HcSdkStatus.unavailable => (
          StatusDotState.error,
          'Health Connect is not available on this device.',
        ),
      },
    };
    return _Line(
      key: const Key('health-availability'),
      dot: dot,
      text: text,
    );
  }
}

class _Access extends StatelessWidget {
  const _Access({required this.health});

  final HealthService health;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final status = health.status!;
    final offered = [
      for (final type in HcDataType.values)
        if (type.feature == null || status.supports(type.feature!)) type,
    ];
    final coverageStart = health.coverageStartMs;
    String grant(String permission, HcFeature feature) =>
        !status.supports(feature)
        ? 'not offered by this Health Connect'
        : status.grantedPermissions.contains(permission)
        ? 'granted'
        : 'not granted';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KV.text(
          key: const Key('health-data-types'),
          label: 'Data types',
          value:
              '${status.readableDataTypes.length} of ${offered.length} '
              'readable',
          meta: 'uploads steps, resting heart rate and sleep',
        ),
        KV.text(
          label: 'Past data',
          value: grant(HcPermissions.readHistory, HcFeature.history),
        ),
        KV.text(
          label: 'Background',
          value: grant(HcPermissions.readInBackground, HcFeature.background),
        ),
        if (!status.historyGranted && coverageStart != null) ...[
          const SizedBox(height: 12),
          Text(
            key: const Key('health-history-off'),
            'Past data off: nothing before ${formatDate(coverageStart)}.',
            style: text$.body.copyWith(color: tokens.inkDim),
          ),
        ],
        if (!status.backgroundGranted && status.readableTypes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Background access off: the sync runs only while Notif is open.',
            style: text$.body.copyWith(color: tokens.inkDim),
          ),
        ],
        if (health.missingPermissions.isNotEmpty) ...[
          const SizedBox(height: 16),
          NotifButton(
            key: const Key('health-grant'),
            label: health.granting
                ? 'Waiting for Health Connect'
                : 'Grant access',
            icon: Icons.lock_open,
            onPressed: health.granting
                ? null
                : () => unawaited(health.grantAccess()),
          ),
        ],
      ],
    );
  }
}

class _Sync extends StatelessWidget {
  const _Sync({required this.health});

  final HealthService health;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final snapshot = health.snapshot;
    final last = snapshot.lastSync;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KV.text(
          key: const Key('health-last-success'),
          label: 'Last success',
          value: switch (snapshot.lastSyncSuccessAtMs) {
            final at? => formatDateTime(at),
            null => 'never',
          },
        ),
        const SizedBox(height: 8),
        if (last == null)
          Text(
            key: const Key('health-last-sync'),
            'No sync has run yet.',
            style: text$.body.copyWith(color: tokens.inkDim),
          )
        else
          _ReportView(key: const Key('health-last-sync'), report: last),
        const SizedBox(height: 16),
        NotifButton(
          key: const Key('health-sync-now'),
          label: snapshot.syncPending ? 'Sync queued' : 'Sync now',
          icon: Icons.sync,
          onPressed: snapshot.syncPending
              ? null
              : () => unawaited(health.syncNow()),
        ),
      ],
    );
  }
}

class _Coverage extends StatelessWidget {
  const _Coverage({required this.health});

  final HealthService health;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final coverage = health.snapshot.coverage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coverage == null)
          Text(
            'No coverage probe yet. It shows which data types Health '
            'Connect holds and how much a year of upload is.',
            style: text$.body.copyWith(color: tokens.inkDim),
          )
        else ...[
          KV.text(
            key: const Key('health-forecast'),
            label: 'Forecast',
            value: '${formatMegabytes(coverage.forecastBytesPerYear)} a year',
            meta: 'probed ${formatDateTime(coverage.computedAtMs)}',
          ),
          for (final MapEntry(:key, :value) in coverage.recordsPerDay.entries)
            KV.text(
              label: key.replaceAll('_', ' '),
              value: '${value.toStringAsFixed(1)} records a day',
            ),
          if (!coverage.historyGranted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Probed without past data: older months are hidden.',
                style: text$.body.copyWith(color: tokens.inkDim),
              ),
            ),
          const SizedBox(height: 12),
          for (final entry in coverage.types)
            if (entry.hasData) _TypeRow(entry: entry),
          if (coverage.types.where((entry) => !entry.hasData).toList()
              case final empty when empty.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No data: ${empty.map((entry) => _label(entry.type)).join(', ')}.',
                style: text$.micro.copyWith(color: tokens.inkMute),
              ),
            ),
        ],
        const SizedBox(height: 16),
        NotifButton(
          key: const Key('health-probe'),
          label: health.probing ? 'Probing' : 'Run coverage probe',
          icon: Icons.query_stats,
          variant: NotifButtonVariant.ghost,
          onPressed: health.probing ? null : () => unawaited(health.runProbe()),
        ),
      ],
    );
  }
}

class _Backfill extends StatelessWidget {
  const _Backfill({required this.health});

  final HealthService health;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final snapshot = health.snapshot;
    final progress = health.backfillProgress;
    final last = snapshot.lastBackfill;
    final complete = last?.backfillComplete ?? false;
    final cursor = snapshot.backfillCursorMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Walks back one week at a time, only while charging on an '
          'unmetered network.',
          style: text$.body.copyWith(color: tokens.inkDim),
        ),
        const SizedBox(height: 12),
        if (snapshot.backfillRequested || complete) ...[
          KV.text(
            key: const Key('health-backfill-progress'),
            label: 'Progress',
            value: complete
                ? 'complete'
                : progress == null
                ? 'waiting to start'
                : '${(progress * 100).toStringAsFixed(0)}%',
            meta: cursor == null ? null : 'back to ${formatDate(cursor)}',
          ),
          if (last != null) _ReportView(report: last),
        ] else
          NotifButton(
            key: const Key('health-start-backfill'),
            label: 'Start backfill',
            icon: Icons.history,
            onPressed: () => unawaited(health.startBackfill()),
          ),
      ],
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report, super.key});

  final HealthRunReport report;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final dot = switch (report.outcome) {
      HealthRunOutcome.succeeded => StatusDotState.synced,
      HealthRunOutcome.partial ||
      HealthRunOutcome.notReady => StatusDotState.warning,
      HealthRunOutcome.failed ||
      HealthRunOutcome.sessionExpired => StatusDotState.error,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Line(
          dot: dot,
          text:
              '${outcomeLabel(report.outcome)} · '
              '${formatDateTime(report.finishedAtMs)}',
        ),
        if (report.outcome == HealthRunOutcome.succeeded ||
            report.outcome == HealthRunOutcome.partial)
          Text(
            '${report.uploadedItems} items in ${report.batches} batches'
            '${report.rejected > 0 ? ', ${report.rejected} skipped' : ''}',
            style: text$.body.copyWith(color: tokens.inkDim),
          ),
        if (report.message case final message?)
          Text(message, style: text$.body.copyWith(color: tokens.inkDim)),
        for (final note in report.notes)
          Text(note, style: text$.micro.copyWith(color: tokens.inkMute)),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.entry});

  final HcTypeCoverage entry;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final detail = entry.byAggregate
        ? '${entry.count} months, ${entry.firstMonth} to ${entry.lastMonth}'
        : '${entry.capped ? 'at least ' : ''}${entry.count} records';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${_label(entry.type)}: $detail',
        style: text$.micro.copyWith(color: tokens.inkDim),
      ),
    );
  }
}

String _label(HcDataType type) => type.wire.replaceAll('_', ' ');

class _Line extends StatelessWidget {
  const _Line({required this.dot, required this.text, super.key});

  final StatusDotState dot;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          StatusDot(state: dot),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: text$.body.copyWith(color: tokens.ink)),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: NotifFeedback.error),
      ),
      child: Text(text, style: text$.body.copyWith(color: tokens.ink)),
    );
  }
}

String outcomeLabel(HealthRunOutcome outcome) => switch (outcome) {
  HealthRunOutcome.succeeded => 'Succeeded',
  HealthRunOutcome.partial => 'Partly done',
  HealthRunOutcome.failed => 'Failed',
  HealthRunOutcome.sessionExpired => 'Signed out',
  HealthRunOutcome.notReady => 'Nothing to do',
};

String formatDate(int ms) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String formatDateTime(int ms) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${formatDate(ms)} ${_two(local.hour)}:${_two(local.minute)}';
}

/// Decimal megabytes, as the plan's budget is stated.
String formatMegabytes(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

String _two(int value) => value.toString().padLeft(2, '0');
