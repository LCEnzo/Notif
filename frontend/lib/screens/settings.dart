import 'package:flutter/material.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
          body: SingleChildScrollView(
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
                  ],
                ),
              ),
            ),
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
