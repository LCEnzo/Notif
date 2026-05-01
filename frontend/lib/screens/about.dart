import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart' show AppSettingsController;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<void> _openUri(Uri uri) async {
    if (await launchUrl(uri)) {
      return;
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open $uri'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = context.watch<AppSettingsController?>();
    final ditheringEnabled = appSettings?.designDitheringEnabled ?? true;

    return Scaffold(
      backgroundColor: NotifDesignTokens.structBg,
      appBar: AppBar(
        backgroundColor: NotifDesignTokens.structSurface,
        foregroundColor: NotifDesignTokens.structText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: NotifDesignTokens.spaceLg,
        title: const Text('About', style: _headlineStyle),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              context.push('/settings');
            },
            icon: const Icon(Icons.settings_sharp),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: NotifDesignTokens.structBorder),
        ),
      ),
      body: Stack(
        children: [
          if (ditheringEnabled) const DitherOverlay(),
          FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (context, snapshot) {
              final packageInfo = snapshot.data;

              return TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 10),
                      child: child,
                    ),
                  );
                },
                child: SelectionArea(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      NotifDesignTokens.spaceLg,
                      NotifDesignTokens.spaceLg,
                      NotifDesignTokens.spaceLg,
                      NotifDesignTokens.spaceBase,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 900;
                            final panels = [
                              _FramedPanel(
                                icon: Icons.radar_sharp,
                                label: 'Page Notes',
                                title: 'Why This Page Exists',
                                child: Text(
                                  'This page is the first deliberate pass at the new non-auth design language. I am using it to work through surfaces, typography, spacing, buttons, and motion before I apply the system more broadly.',
                                  style: _bodyStyle.copyWith(
                                    color: NotifDesignTokens.structText2,
                                  ),
                                ),
                              ),
                              const _FramedPanel(
                                icon: Icons.design_services_sharp,
                                label: 'Design System',
                                title: 'What This Page Tests',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SignalRow(
                                      label: 'Surface',
                                      value:
                                          'Warm dark panels with 1px borders',
                                    ),
                                    SizedBox(height: NotifDesignTokens.spaceSm),
                                    _SignalRow(
                                      label: 'Typography',
                                      value:
                                          'Serif display, sans body, mono metadata',
                                    ),
                                    SizedBox(height: NotifDesignTokens.spaceSm),
                                    _SignalRow(
                                      label: 'Shape',
                                      value:
                                          'Rectangular default, auth-only glass exception',
                                    ),
                                    SizedBox(height: NotifDesignTokens.spaceSm),
                                    _SignalRow(
                                      label: 'Texture',
                                      value:
                                          'Optional scaffold dithering, settings-controlled',
                                    ),
                                    SizedBox(height: NotifDesignTokens.spaceSm),
                                    _SignalRow(
                                      label: 'Motion',
                                      value:
                                          'Fast and quiet, no bounce, no lag',
                                    ),
                                  ],
                                ),
                              ),
                              _FramedPanel(
                                icon: Icons.text_fields_sharp,
                                label: 'Type System',
                                title: 'Typeface Sample',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Printed systems, not dashboards.',
                                      style: _titleStyle,
                                    ),
                                    const SizedBox(
                                      height: NotifDesignTokens.spaceSm,
                                    ),
                                    Text(
                                      'This page uses Instrument Serif for hierarchy, Skyling for body copy, Suisse Mono for compact readouts, and Zalando Sans as the wider utilitarian alternate.',
                                      style: _bodyStyle.copyWith(
                                        color: NotifDesignTokens.structText2,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: NotifDesignTokens.spaceMd,
                                    ),
                                    const Text(
                                      'Pseudo-URI Sample',
                                      style: _labelStyle,
                                    ),
                                    const SizedBox(
                                      height: NotifDesignTokens.spaceXs,
                                    ),
                                    Text(
                                      'notif://about/showcase/non-auth',
                                      style: _monoStyle.copyWith(
                                        color: NotifDesignTokens.accentText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _FramedPanel(
                                icon: Icons.link_sharp,
                                label: 'Contact & Source',
                                title: 'Useful Links',
                                fillChild: isWide,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Text(
                                      'About doubles as the prototype page for the non-auth system, so the key actions live here as first-class components.',
                                      style: _bodyStyle.copyWith(
                                        color: NotifDesignTokens.structText2,
                                      ),
                                    ),
                                    if (isWide)
                                      const Spacer()
                                    else
                                      const SizedBox(
                                        height: NotifDesignTokens.spaceBase,
                                      ),
                                    Wrap(
                                      spacing: NotifDesignTokens.spaceSm,
                                      runSpacing: NotifDesignTokens.spaceSm,
                                      children: [
                                        _ActionButton(
                                          label: 'VIEW SOURCE',
                                          icon: Icons.open_in_new_sharp,
                                          filled: true,
                                          onPressed: () => _openUri(
                                            Uri.parse(
                                              'https://github.com/LCEnzo/Notif',
                                            ),
                                          ),
                                        ),
                                        _ActionButton(
                                          label: 'EMAIL',
                                          icon: Icons.mail_sharp,
                                          onPressed: () => _openUri(
                                            Uri(
                                              scheme: 'mailto',
                                              path: 'lcenzo@protonmail.ch',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHero(
                                  packageInfo: packageInfo,
                                  isLoading:
                                      snapshot.connectionState ==
                                      ConnectionState.waiting,
                                  isWide: isWide,
                                ),
                                const SizedBox(
                                  height: NotifDesignTokens.spaceLg,
                                ),
                                _buildPanelGrid(isWide: isWide, panels: panels),
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

  Widget _buildHero({
    required PackageInfo? packageInfo,
    required bool isLoading,
    required bool isWide,
  }) {
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        const Text('SHOWCASE / NON-AUTH PILOT', style: _labelStyle),
        const SizedBox(height: NotifDesignTokens.spaceSm),
        const Text('About Notif', style: _displayStyle),
        const SizedBox(height: NotifDesignTokens.spaceBase),
        Text(
          'Notif aggregates updates from pages, feeds, and accounts you care about, and notifies you when something changes. Notif is a personal project I made for my own needs, and to expand my skills and experience. As such, it\'s provided as is. '
          'No guarantees that it will work, and I reserve the right to break it at any time without notice.',
          style: _bodyStyle.copyWith(color: NotifDesignTokens.structText2),
        ),
        if (isWide)
          const Spacer()
        else
          const SizedBox(height: NotifDesignTokens.spaceLg),
        _HeroActionRow(
          onGitHub: () =>
              _openUri(Uri.parse('https://github.com/LCEnzo/Notif')),
          onContact: () =>
              _openUri(Uri(scheme: 'mailto', path: 'lcenzo@protonmail.ch')),
        ),
      ],
    );

    final metaCard = _FramedPanel(
      icon: Icons.inventory_2_sharp,
      label: 'Current Build',
      title: 'Prototype Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaRow(
            label: 'Version',
            value: packageInfo == null
                ? null
                : '${packageInfo.version}+${packageInfo.buildNumber}',
            mono: true,
            isLoading: isLoading,
          ),
          const SizedBox(height: NotifDesignTokens.spaceMd),
          const _MetaRow(
            label: 'Fonts',
            value: 'Instrument Serif / Skyling / Zalando Sans / Suisse Mono',
          ),
          const SizedBox(height: NotifDesignTokens.spaceMd),
          const _MetaRow(
            label: 'Motion',
            value: '110–220ms, ease-out, no bounce',
            mono: true,
          ),
        ],
      ),
    );

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          intro,
          const SizedBox(height: NotifDesignTokens.spaceBase),
          metaCard,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: intro),
          const SizedBox(width: NotifDesignTokens.spaceLg),
          Expanded(flex: 3, child: metaCard),
        ],
      ),
    );
  }

  Widget _buildPanelGrid({required bool isWide, required List<Widget> panels}) {
    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < panels.length; index++) ...[
            panels[index],
            if (index != panels.length - 1)
              const SizedBox(height: NotifDesignTokens.spaceBase),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (var index = 0; index < panels.length; index += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: index < panels.length - 1
                  ? [
                      Expanded(child: panels[index]),
                      const SizedBox(width: NotifDesignTokens.spaceBase),
                      Expanded(child: panels[index + 1]),
                    ]
                  : [Expanded(child: panels[index])],
            ),
          ),
          if (index < panels.length - 2)
            const SizedBox(height: NotifDesignTokens.spaceBase),
        ],
      ],
    );
  }
}

class _HeroActionRow extends StatelessWidget {
  final VoidCallback onGitHub;
  final VoidCallback onContact;

  const _HeroActionRow({required this.onGitHub, required this.onContact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HeroActionTile(
            label: 'GITHUB',
            icon: Icons.open_in_new_sharp,
            filled: true,
            onPressed: onGitHub,
          ),
        ),
        const SizedBox(width: NotifDesignTokens.spaceSm),
        const Expanded(child: _HeroActionTile.placeholder()),
        const SizedBox(width: NotifDesignTokens.spaceSm),
        Expanded(
          child: _HeroActionTile(
            label: 'DISCORD',
            icon: Icons.discord,
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: 'lcenzo'));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied Discord handle: lcenzo'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: NotifDesignTokens.spaceSm),
        Expanded(
          child: _HeroActionTile(
            label: 'CONTACT',
            icon: Icons.alternate_email_sharp,
            onPressed: onContact,
          ),
        ),
      ],
    );
  }
}

class _HeroActionTile extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool filled;
  final VoidCallback? onPressed;

  const _HeroActionTile({
    required this.label,
    this.icon,
    this.filled = false,
    this.onPressed,
  });

  const _HeroActionTile.placeholder()
    : label = null,
      icon = null,
      filled = false,
      onPressed = null;

  @override
  Widget build(BuildContext context) {
    final border = filled
        ? BorderSide.none
        : const BorderSide(
            color: NotifDesignTokens.structBorder,
            width: NotifDesignTokens.borderWidth,
          );
    final background = filled
        ? NotifDesignTokens.accentPrimary
        : Colors.transparent;
    final content = label == null
        ? const SizedBox.shrink()
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: filled
                        ? NotifDesignTokens.accentOnAccent
                        : NotifDesignTokens.accentText,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label!,
                  style: NotifDesignTokens.buttonTextStyle.copyWith(
                    color: filled
                        ? NotifDesignTokens.accentOnAccent
                        : NotifDesignTokens.accentText,
                  ),
                ),
              ],
            ),
          );

    Widget tile = Container(
      height: 44,
      decoration: BoxDecoration(
        color: background,
        border: Border.fromBorderSide(border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NotifDesignTokens.spaceSm,
      ),
      alignment: Alignment.center,
      child: content,
    );

    if (onPressed == null) {
      return tile;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onPressed, child: tile),
    );
  }
}

class _FramedPanel extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final Widget child;
  final bool fillChild;

  const _FramedPanel({
    required this.icon,
    required this.label,
    required this.title,
    required this.child,
    this.fillChild = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        border: Border.all(color: NotifDesignTokens.structBorder),
        borderRadius: NotifDesignTokens.flatRadius,
      ),
      padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: NotifDesignTokens.structText2),
              const SizedBox(width: NotifDesignTokens.spaceSm),
              Expanded(child: Text(label, style: _labelStyle)),
            ],
          ),
          const SizedBox(height: NotifDesignTokens.spaceBase),
          Text(title, style: _titleStyle),
          const SizedBox(height: NotifDesignTokens.spaceSm),
          if (fillChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: NotifDesignTokens.framedButtonStyle(isPrimary: filled),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool mono;
  final bool isLoading;

  const _MetaRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: NotifDesignTokens.spaceXs),
        if (isLoading && value == null)
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NotifDesignTokens.accentPrimary,
            ),
          )
        else
          Text(
            value ?? 'Unavailable',
            style: (mono ? _monoStyle : _bodyStyle).copyWith(
              color: NotifDesignTokens.structText,
            ),
          ),
      ],
    );
  }
}

class _SignalRow extends StatelessWidget {
  final String label;
  final String value;

  const _SignalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: NotifDesignTokens.spaceXs),
        Text(
          value,
          style: _bodyStyle.copyWith(color: NotifDesignTokens.structText),
        ),
      ],
    );
  }
}

const TextStyle _displayStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  fontSize: 34,
  height: 42 / 34,
  letterSpacing: -0.5,
  color: NotifDesignTokens.structText,
);

const TextStyle _headlineStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  fontSize: 24,
  height: 30 / 24,
  color: NotifDesignTokens.structText,
);

const TextStyle _titleStyle = TextStyle(
  fontFamily: NotifDesignTokens.displayFont,
  fontSize: 26,
  height: 32 / 26,
  color: NotifDesignTokens.structText,
);

const TextStyle _bodyStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  fontSize: 15,
  height: 22 / 15,
  letterSpacing: 0.1,
  color: NotifDesignTokens.structText,
);

const TextStyle _monoStyle = TextStyle(
  fontFamily: NotifDesignTokens.monoFont,
  fontSize: 14,
  height: 20 / 14,
  color: NotifDesignTokens.structText,
);

const TextStyle _labelStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 16 / 12,
  letterSpacing: 1.2,
  color: NotifDesignTokens.structText2,
);
