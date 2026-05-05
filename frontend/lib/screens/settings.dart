import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _backendUrlController;
  late final AppSettingsController _settings;
  late String _backendUrlSyncedValue;
  String? _backendUrlError;

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppSettingsController>();
    _backendUrlSyncedValue = _settings.customBackendUrl;
    _backendUrlController = TextEditingController(text: _backendUrlSyncedValue);
    _settings.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Consumer<AppSettingsController>(
      builder: (context, settings, _) {
        final userData = context.watch<UserDataService>().userData;
        final hasOpsAccess =
            userData?.isStaff == true || userData?.isSuperuser == true;

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
                  '/ settings',
                  style: text$.micro.copyWith(color: tokens.inkMute),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: tokens.rule),
            ),
          ),
          body: Stack(
            children: [
              if (settings.designDitheringEnabled) const DitherOverlay(),
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Preferences', tone: EyebrowTone.accent),
                        const SizedBox(height: 8),
                        Text(
                          'Look and feel.',
                          style: text$.title.copyWith(color: tokens.ink),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Design-system toggles and network preferences. '
                          'Auth card swapping remains in the debug tuner on '
                          'login and register.',
                          style: text$.body.copyWith(color: tokens.inkDim),
                        ),
                        if (settings.persistenceError != null) ...[
                          const SizedBox(height: 16),
                          _PersistenceBanner(error: settings.persistenceError!),
                        ],
                        const SizedBox(height: 32),

                        const IndexRule(index: 0, title: 'Account'),
                        const SizedBox(height: 8),
                        Text(
                          'Manage your profile, password, and account.',
                          style: text$.body.copyWith(color: tokens.inkDim),
                        ),
                        const SizedBox(height: 12),
                        NotifButton(
                          label: 'Manage account',
                          icon: Icons.person_outline,
                          onPressed: () => context.push('/account'),
                        ),
                        if (hasOpsAccess) ...[
                          const SizedBox(height: 12),
                          NotifButton(
                            label: 'Operations',
                            icon: Icons.admin_panel_settings_outlined,
                            variant: NotifButtonVariant.ghost,
                            onPressed: () => context.push('/ops'),
                          ),
                        ],
                        const SizedBox(height: 32),

                        const IndexRule(index: 1, title: 'Appearance'),
                        _ColorwayPicker(
                          selected: settings.colorway,
                          onChanged: (cw) => settings.setColorway(cw),
                        ),
                        const SizedBox(height: 32),

                        const IndexRule(index: 2, title: 'Typography'),
                        _FontSetPicker(
                          selected: settings.fontSet,
                          onChanged: (fs) => settings.setFontSet(fs),
                        ),
                        const SizedBox(height: 32),

                        const IndexRule(index: 3, title: 'Home density'),
                        _HomeDensityPicker(
                          selected: settings.homeDensity,
                          onChanged: settings.setHomeDensity,
                        ),
                        const SizedBox(height: 32),

                        const IndexRule(index: 4, title: 'Texture'),
                        _LabeledSwitch(
                          title: 'Dithering overlay',
                          description:
                              'A faint dither layer on non-auth scaffolds. Set lower when the texture reads as noise.',
                          value: settings.designDitheringEnabled,
                          onChanged: settings.setDesignDitheringEnabled,
                        ),
                        const SizedBox(height: 32),

                        const IndexRule(index: 5, title: 'Network'),
                        Text(
                          'Backend URL',
                          style: text$.heading.copyWith(color: tokens.ink),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Override the compile-time API URL. Useful for '
                          'testing against a local or remote backend.',
                          style: text$.body.copyWith(color: tokens.inkDim),
                        ),
                        const SizedBox(height: 16),
                        _BackendUrlModeSelector(
                          value: settings.backendUrlMode,
                          onChanged: settings.setBackendUrlMode,
                        ),
                        if (settings.backendUrlMode !=
                            BackendUrlMode.builtin) ...[
                          const SizedBox(height: 16),
                          _UnderlineInput(
                            controller: _backendUrlController,
                            hint: 'http://192.168.1.50:42069/api/v1',
                            errorText: _backendUrlError,
                            onChanged: _setCustomBackendUrl,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleSettingsChanged() {
    _syncBackendUrlController(_settings);
  }

  void _syncBackendUrlController(AppSettingsController settings) {
    final settingsValue = settings.customBackendUrl;
    if (settingsValue == _backendUrlSyncedValue) return;

    final hasLocalEdit = _backendUrlController.text != _backendUrlSyncedValue;
    _backendUrlSyncedValue = settingsValue;
    if (hasLocalEdit) return;

    _backendUrlController.value = TextEditingValue(
      text: settingsValue,
      selection: TextSelection.collapsed(offset: settingsValue.length),
    );
  }

  Future<void> _setCustomBackendUrl(String value) async {
    try {
      await _settings.setCustomBackendUrl(value);
      if (_backendUrlError != null && mounted) {
        setState(() {
          _backendUrlError = null;
        });
      }
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() {
        _backendUrlError = error.message?.toString() ?? 'Invalid URL.';
      });
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Colorway picker — each card previews its own palette directly.
// ═══════════════════════════════════════════════════════════════

class _ColorwayPicker extends StatelessWidget {
  final NotifColorway selected;
  final ValueChanged<NotifColorway> onChanged;

  const _ColorwayPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 640 ? 2 : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final cw in NotifColorway.values)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                child: _ColorwayCard(
                  colorway: cw,
                  selected: cw == selected,
                  onTap: () => onChanged(cw),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ColorwayCard extends StatelessWidget {
  final NotifColorway colorway;
  final bool selected;
  final VoidCallback onTap;

  const _ColorwayCard({
    required this.colorway,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text$ = NotifTextTheme.of(context);
    final preview = NotifTokens.build(colorway);
    final borderColor = selected ? preview.accent : preview.ruleStrong;

    final surface = AspectRatio(
      aspectRatio: 1.42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: preview.bg1,
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.05),
                      radius: 1.16,
                      colors: [
                        preview.halo1,
                        preview.halo2,
                        preview.halo3,
                        preview.bg1,
                      ],
                      stops: const [0, 0.28, 0.56, 0.9],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 44,
                  child: CustomPaint(
                    painter: _HalftoneStripPainter(
                      color: preview.halftone.withValues(alpha: 0.34),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          colorway.code,
                          style: text$.micro.copyWith(color: preview.inkDim),
                        ),
                        if (selected)
                          Text(
                            'ACTIVE',
                            style: text$.micro.copyWith(
                              color: preview.accent,
                              letterSpacing: 1.5,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      colorway.displayName,
                      style: text$.heading.copyWith(color: preview.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      colorway.description,
                      style: text$.body.copyWith(color: preview.inkDim),
                    ),
                    const Spacer(),
                    _Swatches(preview: preview),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: preview.accent.withValues(alpha: 0.08),
        highlightColor: preview.accent.withValues(alpha: 0.04),
        child: selected
            ? CornerMarks(color: preview.ruleStrong, child: surface)
            : surface,
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  final NotifTokens preview;
  const _Swatches({required this.preview});

  @override
  Widget build(BuildContext context) {
    final chips = <Color>[
      preview.bg0,
      preview.bg1,
      preview.bg2,
      preview.halo1,
      preview.accent,
      preview.ink,
    ];
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: chips[i],
                border: Border.all(color: preview.ruleStrong, width: 1),
              ),
            ),
          ),
      ],
    );
  }
}

class _HalftoneStripPainter extends CustomPainter {
  final Color color;

  const _HalftoneStripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = 6.0;

    for (double y = 3; y < size.height + step; y += step) {
      final row = (y / step).floor();
      final radius = 0.7 + (y / size.height) * 0.9;
      final startX = row.isOdd ? step / 2 : 0.0;

      for (double x = startX + 2; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HalftoneStripPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ═══════════════════════════════════════════════════════════════
// Font set picker — three radio rows.
// ═══════════════════════════════════════════════════════════════

class _FontSetPicker extends StatelessWidget {
  final NotifFontSet selected;
  final ValueChanged<NotifFontSet> onChanged;

  const _FontSetPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final set in NotifFontSet.values)
          _FontSetTile(
            set: set,
            selected: set == selected,
            onTap: () => onChanged(set),
          ),
      ],
    );
  }
}

class _FontSetTile extends StatelessWidget {
  final NotifFontSet set;
  final bool selected;
  final VoidCallback onTap;

  const _FontSetTile({
    required this.set,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final preview = NotifTextTheme.forSet(set);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.rule, width: 1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RadioDot(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          set.displayName,
                          style: text$.heading.copyWith(color: tokens.ink),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          set.name.toUpperCase(),
                          style: text$.micro.copyWith(color: tokens.inkMute),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fontRoleSummary(preview),
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aa Bb Cc — Printed systems, not dashboards.',
                      style: preview.bodyLong.copyWith(color: tokens.ink),
                    ),
                    Text(
                      'const handle = \'notif://about/showcase\';',
                      style: preview.code.copyWith(color: tokens.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fontRoleSummary(NotifTextTheme preview) {
  final roles = <(String, String?)>[
    ('Display', preview.display.fontFamily),
    ('Title', preview.title.fontFamily),
    ('Heading', preview.heading.fontFamily),
    ('Eyebrow', preview.eyebrow.fontFamily),
    ('Body', preview.body.fontFamily),
    ('Body long', preview.bodyLong.fontFamily),
    ('Micro', preview.micro.fontFamily),
    ('Code', preview.code.fontFamily),
  ];

  return roles
      .map((role) => '${role.$1}: ${_friendlyFontFamilyName(role.$2)}')
      .join(' · ');
}

String _friendlyFontFamilyName(String? family) {
  switch (family) {
    case NotifFontFamilies.instrumentSerif:
      return 'Instrument Serif';
    case NotifFontFamilies.interTight:
      return 'Inter Tight';
    case NotifFontFamilies.jetBrainsMono:
      return 'JetBrains Mono';
    case NotifFontFamilies.newsreader:
      return 'Newsreader';
    case NotifFontFamilies.skyling:
      return 'Skyling';
    case NotifFontFamilies.zalandoSans:
      return 'Zalando Sans';
    case NotifFontFamilies.suisseMono:
      return 'Suisse Mono';
    case null:
      return 'System';
    default:
      return family;
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? tokens.ink : tokens.ruleStrong,
          width: 1,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: tokens.ink,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class _HomeDensityPicker extends StatelessWidget {
  const _HomeDensityPicker({required this.selected, required this.onChanged});

  final HomeDensity selected;
  final ValueChanged<HomeDensity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HomeDensityTile(
          density: HomeDensity.comfortable,
          selected: selected == HomeDensity.comfortable,
          title: 'Comfortable',
          description:
              'Readable desktop default. Larger rows, bigger actions, fewer ant-sized labels.',
          onTap: () => onChanged(HomeDensity.comfortable),
        ),
        _HomeDensityTile(
          density: HomeDensity.compact,
          selected: selected == HomeDensity.compact,
          title: 'Compact',
          description:
              'Default. Console structure with readable rows and visible actions.',
          onTap: () => onChanged(HomeDensity.compact),
        ),
        _HomeDensityTile(
          density: HomeDensity.dense,
          selected: selected == HomeDensity.dense,
          title: 'Dense',
          description:
              'Tighter than default for scan-heavy sessions and smaller windows.',
          onTap: () => onChanged(HomeDensity.dense),
        ),
      ],
    );
  }
}

class _HomeDensityTile extends StatelessWidget {
  const _HomeDensityTile({
    required this.density,
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final HomeDensity density;
  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.rule)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RadioDot(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: text$.heading.copyWith(color: tokens.ink),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          density.name.toUpperCase(),
                          style: text$.micro.copyWith(color: tokens.inkMute),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Labeled switch — custom so it doesn't pick up Material's
// defaults. Uses body copy + hairline divider, matches IndexRule rhythm.
// ═══════════════════════════════════════════════════════════════

class _LabeledSwitch extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LabeledSwitch({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text$.heading.copyWith(color: tokens.ink)),
              const SizedBox(height: 4),
              Text(
                description,
                style: text$.body.copyWith(color: tokens.inkDim),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: tokens.accent,
          activeTrackColor: tokens.accent.withValues(alpha: 0.4),
          inactiveThumbColor: tokens.inkDim,
          inactiveTrackColor: tokens.rule,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Backend-URL mode — radio group preserving the existing enum UX.
// ═══════════════════════════════════════════════════════════════

class _BackendUrlModeSelector extends StatelessWidget {
  final BackendUrlMode value;
  final ValueChanged<BackendUrlMode> onChanged;

  const _BackendUrlModeSelector({required this.value, required this.onChanged});

  static const _modeLabels = {
    BackendUrlMode.builtin: 'Built-in URL only',
    BackendUrlMode.customWithFallback: 'Custom URL, built-in as fallback',
    BackendUrlMode.customOnly: 'Custom URL only',
  };

  static const _modeDescriptions = {
    BackendUrlMode.builtin: 'Use the compile-time API URL.',
    BackendUrlMode.customWithFallback:
        'Try your custom URL first. If it fails, retry with the built-in URL.',
    BackendUrlMode.customOnly:
        'Only use your custom URL. Requests fail if it is unreachable.',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mode in BackendUrlMode.values)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(mode),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RadioDot(selected: mode == value),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _modeLabels[mode]!,
                            style: text$.body.copyWith(
                              color: mode == value ? tokens.ink : tokens.inkDim,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _modeDescriptions[mode]!,
                            style: text$.micro.copyWith(color: tokens.inkMute),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Underline input — the "Input" primitive's form for Settings.
// ═══════════════════════════════════════════════════════════════

class _UnderlineInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? errorText;
  final ValueChanged<String> onChanged;

  const _UnderlineInput({
    required this.controller,
    required this.hint,
    this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NotifTextField(
      controller: controller,
      hint: hint,
      errorText: errorText,
      variant: NotifInputVariant.underline,
      onChanged: (value) {
        onChanged(value);

        final trimmed = value.trim();
        if (trimmed == value) return;

        controller.value = TextEditingValue(
          text: trimmed,
          selection: TextSelection.collapsed(offset: trimmed.length),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Persistence error banner — surfaces SharedPreferences failures.
// ═══════════════════════════════════════════════════════════════

class _PersistenceBanner extends StatelessWidget {
  final AppSettingsPersistenceException error;
  const _PersistenceBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.bg2,
        border: Border.all(color: NotifFeedback.error, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Persistence error', tone: EyebrowTone.accent),
          const SizedBox(height: 4),
          Text(
            'Changes are active this session but could not be saved.',
            style: text$.body.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '${error.operation}: ${error.cause}',
            style: text$.code.copyWith(color: tokens.inkDim),
          ),
        ],
      ),
    );
  }
}
