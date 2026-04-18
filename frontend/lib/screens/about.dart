import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart' show AppSettingsController;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  final Future<PackageInfo>? packageInfoFuture;

  const AboutPage({super.key, this.packageInfoFuture});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = widget.packageInfoFuture ?? PackageInfo.fromPlatform();
  }

  Future<void> _openUri(Uri uri) async {
    // launchUrl can throw (e.g., no handler registered) — report rather
    // than swallow. We still show a snackbar in the recoverable "false"
    // case; unexpected exceptions propagate to a visible error.
    final bool launched;
    try {
      launched = await launchUrl(uri);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Launcher error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (launched) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open $uri'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    final appSettings = context.watch<AppSettingsController?>();
    final ditheringEnabled = appSettings?.designDitheringEnabled ?? true;

    return Scaffold(
      backgroundColor: tokens.bg1,
      appBar: AppBar(
        backgroundColor: tokens.bg1,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
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
            Text('/ about', style: text$.micro.copyWith(color: tokens.inkMute)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/Settings'),
            icon: Icon(Icons.settings_sharp, color: tokens.inkDim),
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
          FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (context, snapshot) {
              final packageInfo = snapshot.data;
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              if (snapshot.hasError) {
                return _ErrorSlab(error: snapshot.error!);
              }
              return TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 10),
                    child: child,
                  ),
                ),
                child: SelectionArea(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 900;
                            void onGitHub() {
                              _openUri(
                                Uri.parse('https://github.com/LCEnzo/Notif'),
                              );
                            }

                            void onContact() {
                              _openUri(
                                Uri(
                                  scheme: 'mailto',
                                  path: 'lcenzo@protonmail.ch',
                                ),
                              );
                            }

                            final sections = [
                              const _AboutSection(
                                key: ValueKey('aboutSectionPageNotes'),
                                header: IndexRule(
                                  index: 1,
                                  title: 'Page notes',
                                ),
                                child: _IntroCard(),
                              ),
                              _AboutSection(
                                key: const ValueKey('aboutSectionDesignSystem'),
                                header: const IndexRule(
                                  index: 2,
                                  title: 'Design system',
                                ),
                                child: _SystemGrid(isWide: isWide),
                              ),
                              const _AboutSection(
                                key: ValueKey('aboutSectionTypography'),
                                header: IndexRule(
                                  index: 3,
                                  title: 'Typography',
                                ),
                                child: _TypefaceCard(),
                              ),
                              _AboutSection(
                                key: const ValueKey('aboutSectionContact'),
                                header: const IndexRule(
                                  index: 4,
                                  title: 'Contact & source',
                                ),
                                child: _ContactRow(
                                  onGitHub: onGitHub,
                                  onContact: onContact,
                                ),
                              ),
                            ];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Hero(
                                  packageInfo: packageInfo,
                                  isLoading: isLoading,
                                  isWide: isWide,
                                  onGitHub: onGitHub,
                                  onContact: onContact,
                                ),
                                const SizedBox(height: 48),
                                _AboutSections(
                                  isWide: isWide,
                                  maxWidth: constraints.maxWidth,
                                  sections: sections,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Hero — oversized serif title with a meta card (CornerMarks).
// ═══════════════════════════════════════════════════════════════

class _Hero extends StatelessWidget {
  final PackageInfo? packageInfo;
  final bool isLoading;
  final bool isWide;
  final VoidCallback onGitHub;
  final VoidCallback onContact;

  const _Hero({
    required this.packageInfo,
    required this.isLoading,
    required this.isWide,
    required this.onGitHub,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('Showcase · non-auth pilot', tone: EyebrowTone.accent),
        const SizedBox(height: 12),
        Text('About Notif', style: text$.display.copyWith(color: tokens.ink)),
        const SizedBox(height: 16),
        Text(
          'Notif aggregates updates from pages, feeds, and accounts you care '
          'about, and surfaces them when something changes. It is a personal '
          'project built for my own needs and to sharpen the craft.',
          style: text$.bodyLong.copyWith(color: tokens.inkDim),
        ),
        const SizedBox(height: 12),
        Text(
          'No guarantees it will work. I reserve the right to break it at any '
          'time without notice.',
          style: text$.bodyLong.copyWith(color: tokens.inkDim),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            NotifButton(
              label: 'View source',
              icon: Icons.open_in_new_sharp,
              onPressed: onGitHub,
              variant: NotifButtonVariant.primary,
            ),
            const SizedBox(width: 12),
            NotifButton(
              label: 'Contact',
              icon: Icons.alternate_email_sharp,
              onPressed: onContact,
              variant: NotifButtonVariant.ghost,
            ),
          ],
        ),
      ],
    );

    final meta = NotifCard(
      cornerMarks: true,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Current build'),
          const SizedBox(height: 8),
          Text(
            'Prototype status',
            style: text$.heading.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 16),
          _VersionRow(
            label: 'Version',
            packageInfo: packageInfo,
            isLoading: isLoading,
          ),
          const KV(label: 'Scheme', value: _ActiveSchemeText()),
          const KV(
            label: 'Motion',
            value: _StaticText('110–220ms, ease-out, no bounce'),
          ),
        ],
      ),
    );

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [intro, const SizedBox(height: 24), meta],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: intro),
          const SizedBox(width: 32),
          Expanded(flex: 3, child: meta),
        ],
      ),
    );
  }
}

class _AboutSections extends StatelessWidget {
  final bool isWide;
  final double maxWidth;
  final List<Widget> sections;

  const _AboutSections({
    required this.isWide,
    required this.maxWidth,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            sections[i],
            if (i != sections.length - 1) const SizedBox(height: 32),
          ],
        ],
      );
    }

    const gap = 32.0;
    final itemWidth = (maxWidth - gap) / 2;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final section in sections)
          SizedBox(width: itemWidth, child: section),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  final Widget header;
  final Widget child;

  const _AboutSection({required this.header, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, child],
    );
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final PackageInfo? packageInfo;
  final bool isLoading;

  const _VersionRow({
    required this.label,
    required this.packageInfo,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final versionText = packageInfo == null
        ? 'Unavailable'
        : '${packageInfo!.version}+${packageInfo!.buildNumber}';

    return KV(
      label: label,
      value: isLoading && packageInfo == null
          ? _LoadingVersionText(color: NotifTokens.of(context).accent)
          : _VersionText(text: versionText),
    );
  }
}

class _InlineSpinner extends StatelessWidget {
  final Color color;
  const _InlineSpinner({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
    );
  }
}

class _LoadingVersionText extends StatelessWidget {
  final Color color;

  const _LoadingVersionText({required this.color});

  @override
  Widget build(BuildContext context) {
    final text$ = NotifTextTheme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _InlineSpinner(color: color),
            ),
          ),
          const TextSpan(text: 'Loading…'),
        ],
      ),
      style: text$.code.copyWith(color: color),
    );
  }
}

class _VersionText extends StatelessWidget {
  final String text;
  const _VersionText({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    return Text(text, style: text$.code.copyWith(color: tokens.accent));
  }
}

class _StaticText extends StatelessWidget {
  final String text;
  const _StaticText(this.text);

  @override
  Widget build(BuildContext context) => Text(text);
}

class _ActiveSchemeText extends StatelessWidget {
  const _ActiveSchemeText();

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    return Text('${tokens.colorway.displayName} · ${tokens.scheme.name}');
  }
}

// ═══════════════════════════════════════════════════════════════
// Narrative & system sections
// ═══════════════════════════════════════════════════════════════

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return NotifCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Why this page exists'),
          const SizedBox(height: 12),
          Text(
            'About is the testbed for the non-auth design language.',
            style: text$.heading.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 12),
          Text(
            'Surfaces, typography, spacing, buttons, and motion all get '
            'exercised here before the system is applied more broadly. If a '
            'decision feels wrong on this page, it is wrong everywhere.',
            style: text$.bodyLong.copyWith(color: tokens.inkDim),
          ),
        ],
      ),
    );
  }
}

class _SystemGrid extends StatelessWidget {
  final bool isWide;
  const _SystemGrid({required this.isWide});

  static const _rows = [
    _SignalRow(
      label: 'Surface',
      value: 'Printed panels, translucent hairlines.',
    ),
    _SignalRow(
      label: 'Typography',
      value: 'Serif display, mono body, mono metadata.',
    ),
    _SignalRow(
      label: 'Shape',
      value: 'Rectangular default; auth-only 6dp glass exception.',
    ),
    _SignalRow(
      label: 'Texture',
      value: 'Optional scaffold dithering, settings-controlled.',
    ),
    _SignalRow(label: 'Motion', value: 'Fast and quiet, no bounce, no lag.'),
    _SignalRow(
      label: 'Borders',
      value: 'Hairlines carry elevation in place of shadow.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final columns = isWide ? 2 : 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 16.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final row in _rows)
              SizedBox(
                width: itemWidth,
                child: NotifCard(child: row),
              ),
          ],
        );
      },
    );
  }
}

class _SignalRow extends StatelessWidget {
  final String label;
  final String value;
  const _SignalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 8),
        Text(value, style: text$.body.copyWith(color: tokens.ink)),
      ],
    );
  }
}

class _TypefaceCard extends StatelessWidget {
  const _TypefaceCard();

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return NotifCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Typeface sample'),
          const SizedBox(height: 12),
          Text(
            'Printed systems, not dashboards.',
            style: text$.title.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 12),
          Text(
            'The active font set is chosen in Settings. Roles resolve through '
            'the Theme extension, so changing set updates every surface at '
            'once without touching the screens.',
            style: text$.bodyLong.copyWith(color: tokens.inkDim),
          ),
          const SizedBox(height: 20),
          Eyebrow('Pseudo-URI sample'),
          const SizedBox(height: 6),
          Text(
            'notif://about/showcase/non-auth',
            style: text$.code.copyWith(color: tokens.accent),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Tag('Colorway', tone: TagTone.defaultTone),
              const SizedBox(width: 6),
              Tag(tokens.colorway.displayName, tone: TagTone.accent),
              const SizedBox(width: 6),
              Tag(tokens.scheme.name, tone: TagTone.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final VoidCallback onGitHub;
  final VoidCallback onContact;

  const _ContactRow({required this.onGitHub, required this.onContact});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return NotifCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Links'),
          const SizedBox(height: 12),
          Text('Talk to me.', style: text$.heading.copyWith(color: tokens.ink)),
          const SizedBox(height: 8),
          Text(
            'About doubles as the prototype for the non-auth system, so the '
            'key actions live here as first-class components.',
            style: text$.body.copyWith(color: tokens.inkDim),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              NotifButton(
                label: 'GitHub',
                icon: Icons.open_in_new_sharp,
                onPressed: onGitHub,
                variant: NotifButtonVariant.primary,
              ),
              NotifButton(
                label: 'Email',
                icon: Icons.mail_sharp,
                onPressed: onContact,
                variant: NotifButtonVariant.ghost,
              ),
              NotifButton(
                label: 'Copy Discord',
                icon: Icons.discord,
                onPressed: () => _copyDiscord(context),
                variant: NotifButtonVariant.ghost,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyDiscord(BuildContext context) async {
    try {
      await Clipboard.setData(const ClipboardData(text: 'lcenzo'));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clipboard error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied Discord handle: lcenzo'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Error slab — replaces the body when PackageInfo fails outright.
// ═══════════════════════════════════════════════════════════════

class _ErrorSlab extends StatelessWidget {
  final Object error;
  const _ErrorSlab({required this.error});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Error', tone: EyebrowTone.accent),
              const SizedBox(height: 8),
              Text(
                'Could not load build info.',
                style: text$.heading.copyWith(color: tokens.ink),
              ),
              const SizedBox(height: 8),
              Text('$error', style: text$.code.copyWith(color: tokens.inkDim)),
            ],
          ),
        ),
      ),
    );
  }
}
