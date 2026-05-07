import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/commons/url_launcher_helper.dart';
import 'package:notif/services/app_settings.dart' show AppSettingsController;
import 'package:notif/services/auth.dart' show AuthService;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

const String _buildGitHash = String.fromEnvironment(
  'GIT_HASH',
  defaultValue: 'dev',
);

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
    await openUriSafely(context, uri);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    final appSettings = context.watch<AppSettingsController?>();
    final ditheringEnabled = appSettings?.designDitheringEnabled ?? true;
    final loggedIn = context.watch<AuthService?>()?.jwt != null;

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
              'Notif',
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
          if (loggedIn)
            IconButton(
              tooltip: 'Settings',
              onPressed: () {
                context.push('/settings');
              },
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
                              _AboutSection(
                                key: const ValueKey('aboutSectionPageNotes'),
                                isWide: isWide,
                                header: const IndexRule(
                                  index: 1,
                                  title: 'Page notes',
                                ),
                                child: const _IntroCard(),
                              ),
                              _AboutSection(
                                key: const ValueKey('aboutSectionDesignSystem'),
                                isWide: isWide,
                                header: const IndexRule(
                                  index: 2,
                                  title: 'Design system',
                                ),
                                child: const _SystemGrid(),
                              ),
                              _AboutSection(
                                key: const ValueKey('aboutSectionTypography'),
                                isWide: isWide,
                                header: const IndexRule(
                                  index: 3,
                                  title: 'Typography',
                                ),
                                child: const _TypefaceCard(),
                              ),
                              _AboutSection(
                                key: const ValueKey('aboutSectionContact'),
                                isWide: isWide,
                                header: const IndexRule(
                                  index: 4,
                                  title: 'Contact & source',
                                ),
                                child: _ContactRow(
                                  isWide: isWide,
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
                                const SizedBox(height: 32),
                                _AboutSections(
                                  isWide: isWide,
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

    final introTop = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Showcase · non-auth pilot', tone: EyebrowTone.accent),
        const SizedBox(height: 12),
        Text('About Notif', style: text$.display.copyWith(color: tokens.ink)),
        const SizedBox(height: 16),
        Text(
          'Notif aggregates updates from pages, feeds, and accounts you care '
          'about, and surfaces them when something changes. It is a personal '
          'project built for my own needs and to sharpen the craft. As such, '
          'it is provided as-is. No guarantees it will work. I reserve the '
          'right to break it at any time without notice.',
          style: text$.bodyLong.copyWith(color: tokens.inkDim),
        ),
      ],
    );
    final introBottom = _HeroActionGrid(
      isWide: isWide,
      onGitHub: onGitHub,
      onContact: onContact,
    );
    final intro = Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: isWide
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        introTop,
        if (!isWide) const SizedBox(height: 24),
        introBottom,
      ],
    );

    final meta = NotifCard(
      cornerMarks: true,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Current build'),
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
          const KV(label: 'Commit', value: _BuildCommitText()),
          const KV(label: 'Colorway', value: _ActiveColorwayText()),
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
          Expanded(
            flex: 5,
            child: KeyedSubtree(
              key: const ValueKey('aboutHeroIntro'),
              child: intro,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 3,
            child: KeyedSubtree(
              key: const ValueKey('aboutHeroMeta'),
              child: meta,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSections extends StatelessWidget {
  final bool isWide;
  final List<Widget> sections;

  const _AboutSections({required this.isWide, required this.sections});

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

    return Column(
      children: [
        for (var index = 0; index < sections.length; index += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: index < sections.length - 1
                  ? [
                      Expanded(child: sections[index]),
                      const SizedBox(width: 24),
                      Expanded(child: sections[index + 1]),
                    ]
                  : [Expanded(child: sections[index])],
            ),
          ),
          if (index < sections.length - 2) const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  final bool isWide;
  final Widget header;
  final Widget child;

  const _AboutSection({
    required this.isWide,
    required this.header,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (isWide) Expanded(child: child) else child,
      ],
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

class _BuildCommitText extends StatelessWidget {
  const _BuildCommitText();

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    return Text(
      _buildGitHash,
      style: text$.code.copyWith(color: tokens.accent),
    );
  }
}

class _StaticText extends StatelessWidget {
  final String text;
  const _StaticText(this.text);

  @override
  Widget build(BuildContext context) => Text(text);
}

class _ActiveColorwayText extends StatelessWidget {
  const _ActiveColorwayText();

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    return Text('${tokens.colorway.displayName} · ${tokens.brightness.name}');
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
          const _CardLead(icon: Icons.radar_sharp, label: 'Page notes'),
          const SizedBox(height: 12),
          Text(
            'Why this page exists',
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
  const _SystemGrid();

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
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return NotifCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLead(
            icon: Icons.design_services_sharp,
            label: 'Design system',
          ),
          const SizedBox(height: 12),
          Text(
            'What this page tests',
            style: text$.heading.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _rows.length; i++) ...[
            _rows[i],
            if (i != _rows.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
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
          const _CardLead(icon: Icons.text_fields_sharp, label: 'Type system'),
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
          const Eyebrow('Pseudo-URI sample'),
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
              Tag(tokens.brightness.name, tone: TagTone.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final bool isWide;
  final VoidCallback onGitHub;
  final VoidCallback onContact;

  const _ContactRow({
    required this.isWide,
    required this.onGitHub,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final wideButtons = Row(
      children: [
        Expanded(
          child: NotifButton(
            label: 'GitHub',
            icon: Icons.open_in_new_sharp,
            onPressed: onGitHub,
            variant: NotifButtonVariant.primary,
            expand: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: NotifButton(
            label: 'Email',
            icon: Icons.mail_sharp,
            onPressed: onContact,
            variant: NotifButtonVariant.ghost,
            expand: true,
          ),
        ),
      ],
    );
    final narrowButtons = Wrap(
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
      ],
    );

    return NotifCard(
      child: isWide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _CardLead(
                      icon: Icons.link_sharp,
                      label: 'Contact & source',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Useful links.',
                      style: text$.heading.copyWith(color: tokens.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'About doubles as the prototype for the non-auth system, '
                      'so the key actions live here as first-class '
                      'components.',
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                  ],
                ),
                wideButtons,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardLead(
                  icon: Icons.link_sharp,
                  label: 'Contact & source',
                ),
                const SizedBox(height: 12),
                Text(
                  'Useful links.',
                  style: text$.heading.copyWith(color: tokens.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'About doubles as the prototype for the non-auth system, so '
                  'the key actions live here as first-class components.',
                  style: text$.body.copyWith(color: tokens.inkDim),
                ),
                const SizedBox(height: 20),
                narrowButtons,
              ],
            ),
    );
  }
}

class _HeroActionGrid extends StatelessWidget {
  final bool isWide;
  final VoidCallback onGitHub;
  final VoidCallback onContact;

  const _HeroActionGrid({
    required this.isWide,
    required this.onGitHub,
    required this.onContact,
  });

  List<Widget> _buildChildren(BuildContext context) {
    return <Widget>[
      NotifButton(
        key: const ValueKey('aboutHeroActionGitHub'),
        label: 'GitHub',
        icon: Icons.open_in_new_sharp,
        onPressed: onGitHub,
        variant: NotifButtonVariant.primary,
        expand: true,
      ),
      const _HeroActionPlaceholder(key: ValueKey('aboutHeroActionPlaceholder')),
      NotifButton(
        key: const ValueKey('aboutHeroActionDiscord'),
        label: 'Discord',
        icon: Icons.discord,
        onPressed: () => _copyDiscordHandle(context),
        variant: NotifButtonVariant.ghost,
        expand: true,
      ),
      NotifButton(
        key: const ValueKey('aboutHeroActionContact'),
        label: 'Contact',
        icon: Icons.alternate_email_sharp,
        onPressed: onContact,
        variant: NotifButtonVariant.ghost,
        expand: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = _buildChildren(context);

    if (isWide) {
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i != children.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = 2;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _HeroActionPlaceholder extends StatelessWidget {
  const _HeroActionPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.rule, width: 1),
      ),
    );
  }
}

class _CardLead extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CardLead({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: tokens.inkDim),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: text$.eyebrow.copyWith(color: tokens.inkMute),
        ),
      ],
    );
  }
}

Future<void> _copyDiscordHandle(BuildContext context) async {
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
              const Eyebrow('Error', tone: EyebrowTone.accent),
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
