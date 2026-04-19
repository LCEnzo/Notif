import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    if (authService.jwt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/LogIn');
        }
      });

      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final appSettings = context.watch<AppSettingsController?>();
    final userData = context.watch<UserDataService>().userData;
    final ditheringEnabled = appSettings?.designDitheringEnabled ?? true;

    return Scaffold(
      backgroundColor: tokens.bg0,
      appBar: AppBar(
        backgroundColor: tokens.bg0,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 24,
        title: Row(
          children: [
            Text(
              'notif',
              style: text$.heading.copyWith(
                color: tokens.ink,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 8),
            Text('/ feed', style: text$.micro.copyWith(color: tokens.inkMute)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: () => _showStubSnackBar(
              context,
              'Feed filters are not wired yet.',
            ),
            icon: Icon(Icons.filter_alt_outlined, color: tokens.inkDim),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: () => _showStubSnackBar(
              context,
              'Feed search is not wired yet.',
            ),
            icon: Icon(Icons.search_sharp, color: tokens.inkDim),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/Settings'),
            icon: Icon(Icons.settings_sharp, color: tokens.inkDim),
          ),
          PopupMenuButton<_HomeMenuAction>(
            tooltip: 'More',
            color: tokens.bg3,
            surfaceTintColor: Colors.transparent,
            itemBuilder: (context) => [
              PopupMenuItem<_HomeMenuAction>(
                value: _HomeMenuAction.about,
                child: Text(
                  'About',
                  style: text$.body.copyWith(color: tokens.ink),
                ),
              ),
              PopupMenuItem<_HomeMenuAction>(
                value: _HomeMenuAction.logout,
                child: Text(
                  'Log out',
                  style: text$.body.copyWith(color: tokens.ink),
                ),
              ),
            ],
            onSelected: (action) {
              switch (action) {
                case _HomeMenuAction.about:
                  Navigator.pushNamed(context, '/About');
                  break;
                case _HomeMenuAction.logout:
                  authService.logout();
                  Navigator.pushReplacementNamed(context, '/LogIn');
                  break;
              }
            },
            icon: Icon(Icons.more_horiz_sharp, color: tokens.inkDim),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tokens.rule),
        ),
      ),
      body: Stack(
        children: [
          if (ditheringEnabled) const DitherOverlay(),
          Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: userData == null
                          ? const _HomeLoadingState()
                          : _HomeEmptyState(userData: userData),
                    ),
                  ),
                ),
              ),
              _HomeFooter(userData: userData),
            ],
          ),
        ],
      ),
    );
  }
}

enum _HomeMenuAction { about, logout }

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: tokens.accent,
          ),
        ),
        const SizedBox(height: 20),
        Eyebrow('Loading profile', tone: EyebrowTone.accent),
        const SizedBox(height: 12),
        Text(
          'Preparing the feed shell.',
          textAlign: TextAlign.center,
          style: text$.title.copyWith(
            color: tokens.ink,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your account is authenticated. User details are still loading '
          'before the home view can settle.',
          textAlign: TextAlign.center,
          style: text$.body.copyWith(color: tokens.inkDim),
        ),
      ],
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  final UserData userData;

  const _HomeEmptyState({required this.userData});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final orbSize = width < 600 ? 160.0 : 220.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: 0.85,
          child: _SignalOrb(size: orbSize),
        ),
        const SizedBox(height: 28),
        Eyebrow('All clear', tone: EyebrowTone.accent),
        const SizedBox(height: 14),
        Text(
          'No new signal.',
          textAlign: TextAlign.center,
          style: text$.title.copyWith(
            color: tokens.ink,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: text$.body.copyWith(color: tokens.inkDim, height: 1.7),
            children: [
              const TextSpan(text: 'Signed in as '),
              TextSpan(
                text: '@${userData.username}',
                style: text$.body.copyWith(color: tokens.ink),
              ),
              const TextSpan(
                text: '. Sources and digests are not wired yet, so this feed '
                    'shell is waiting on the next backend pass. Until then, '
                    'consider going outside.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            NotifButton(
              label: 'Manage sources',
              icon: Icons.rss_feed_sharp,
              onPressed: () => _showStubSnackBar(
                context,
                'Source management is not wired yet.',
              ),
              variant: NotifButtonVariant.ghost,
            ),
            NotifButton(
              label: 'Add a source',
              icon: Icons.add_sharp,
              onPressed: () => _showStubSnackBar(
                context,
                'Adding sources is not wired yet.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            const Tag('Feed shell', tone: TagTone.defaultTone),
            Tag(userData.name.isEmpty ? userData.username : userData.name),
            Tag(tokens.colorway.displayName, tone: TagTone.accent),
          ],
        ),
      ],
    );
  }
}

class _HomeFooter extends StatelessWidget {
  final UserData? userData;

  const _HomeFooter({required this.userData});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.rule, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                    'sources pending'.toUpperCase(),
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

class _SignalOrb extends StatelessWidget {
  final double size;

  const _SignalOrb({required this.size});

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
  final Color ink;
  final Color accent;

  const _SignalOrbPainter({
    required this.ink,
    required this.accent,
  });

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

void _showStubSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
