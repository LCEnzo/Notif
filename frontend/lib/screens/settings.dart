import 'package:flutter/material.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _backendUrlController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppSettingsController>();
    _backendUrlController = TextEditingController(
      text: settings.customBackendUrl,
    );
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsController>(
      builder: (context, settings, _) {
        return Scaffold(
          backgroundColor: NotifDesignTokens.structBg,
          appBar: AppBar(
            backgroundColor: NotifDesignTokens.structSurface,
            foregroundColor: NotifDesignTokens.structText,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: NotifDesignTokens.spaceLg,
            title: const Text('Settings', style: _headlineStyle),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: NotifDesignTokens.structBorder,
              ),
            ),
          ),
          body: Stack(
            children: [
              if (settings.designDitheringEnabled) const DitherOverlay(),
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  NotifDesignTokens.spaceLg,
                  NotifDesignTokens.spaceLg,
                  NotifDesignTokens.spaceLg,
                  NotifDesignTokens.space2xl,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Padding(
                      padding:
                          const EdgeInsets.only(bottom: NotifDesignTokens.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text('Preferences', style: _displayStyle),
                        const SizedBox(height: NotifDesignTokens.spaceBase),
                        Text(
                          'Settings holds design-system toggles that are safe to experiment with outside auth. Auth card swapping remains in the debug tuner on login and register.',
                          style: _bodyStyle.copyWith(
                            color: NotifDesignTokens.structText2,
                          ),
                        ),
                        const SizedBox(height: NotifDesignTokens.spaceLg),
                        _SettingsPanel(
                          label: 'Design System Pilot',
                          title: 'Surface Texture',
                          child: SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeThumbColor: NotifDesignTokens.accentPrimary,
                            activeTrackColor: NotifDesignTokens.accentPrimary
                                .withValues(alpha: 0.4),
                            inactiveThumbColor: NotifDesignTokens.structText2,
                            inactiveTrackColor: NotifDesignTokens.structDivider,
                            title: const Text(
                              'Enable dithering',
                              style: _titleStyle,
                            ),
                            subtitle: Text(
                              'Adds a faint dither layer to the non-auth showcase treatment on About. Keep it subtle.',
                              style: _bodyStyle.copyWith(
                                color: NotifDesignTokens.structText2,
                              ),
                            ),
                            value: settings.designDitheringEnabled,
                            onChanged: (enabled) {
                              settings.setDesignDitheringEnabled(enabled);
                            },
                          ),
                        ),
                        const SizedBox(height: NotifDesignTokens.spaceLg),
                        _SettingsPanel(
                          label: 'Network',
                          title: 'Backend URL',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Override the compile-time API URL with a custom address. Useful for testing against a local or remote backend.',
                                style: _bodyStyle.copyWith(
                                  color: NotifDesignTokens.structText2,
                                ),
                              ),
                              const SizedBox(
                                height: NotifDesignTokens.spaceBase,
                              ),
                              _BackendUrlModeSelector(
                                value: settings.backendUrlMode,
                                onChanged: settings.setBackendUrlMode,
                              ),
                              if (settings.backendUrlMode !=
                                  BackendUrlMode.builtin) ...[
                                const SizedBox(
                                  height: NotifDesignTokens.spaceBase,
                                ),
                                TextField(
                                  controller: _backendUrlController,
                                  style: _monoStyle,
                                  cursorColor: NotifDesignTokens.accentText,
                                  decoration: InputDecoration(
                                    hintText:
                                        'http://192.168.1.50:42069/api/v1',
                                    hintStyle: _monoStyle.copyWith(
                                      color: NotifDesignTokens.structText3,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: NotifDesignTokens.spaceMd,
                                      vertical: NotifDesignTokens.spaceMd,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(
                                        color: NotifDesignTokens.structBorder,
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(
                                        color: NotifDesignTokens.accentDim,
                                        width:
                                            NotifDesignTokens.borderFocusWidth,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    settings.setCustomBackendUrl(value);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        ],
                      ),
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
}

class _SettingsPanel extends StatelessWidget {
  final String label;
  final String title;
  final Widget child;

  const _SettingsPanel({
    required this.label,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NotifDesignTokens.structSurface,
        border: Border.all(color: NotifDesignTokens.structBorder),
      ),
      padding: const EdgeInsets.all(NotifDesignTokens.spaceBase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _labelStyle),
          const SizedBox(height: NotifDesignTokens.spaceSm),
          Text(title, style: _titleStyle),
          const SizedBox(height: NotifDesignTokens.spaceSm),
          child,
        ],
      ),
    );
  }
}

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
    return RadioGroup<BackendUrlMode>(
      groupValue: value,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mode in BackendUrlMode.values)
            _buildTile(mode, mode == value),
        ],
      ),
    );
  }

  Widget _buildTile(BackendUrlMode mode, bool selected) {
    return InkWell(
      onTap: () => onChanged(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: NotifDesignTokens.spaceSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<BackendUrlMode>(
              value: mode,
              activeColor: NotifDesignTokens.accentPrimary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: NotifDesignTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _modeLabels[mode]!,
                    style: _bodyStyle.copyWith(
                      color: selected
                          ? NotifDesignTokens.structText
                          : NotifDesignTokens.structText2,
                    ),
                  ),
                  const SizedBox(height: NotifDesignTokens.spaceXs / 2),
                  Text(_modeDescriptions[mode]!, style: _captionStyle),
                ],
              ),
            ),
          ],
        ),
      ),
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
  fontSize: 20,
  height: 26 / 20,
  color: NotifDesignTokens.structText,
);

const TextStyle _bodyStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  fontSize: 15,
  height: 22 / 15,
  letterSpacing: 0.1,
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

const TextStyle _captionStyle = TextStyle(
  fontFamily: NotifDesignTokens.bodyFont,
  fontSize: 13,
  height: 18 / 13,
  color: NotifDesignTokens.structText3,
);

const TextStyle _monoStyle = TextStyle(
  fontFamily: NotifDesignTokens.monoFont,
  fontSize: 14,
  height: 20 / 14,
  color: NotifDesignTokens.structText,
);
