import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notif/commons/auth_background.dart';
import 'package:notif/commons/auth_palette.dart';

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

AuthTextureTunerController enableAuthTextureTuner() {
  final controller = AuthTextureTunerController();
  PageBackground.debugSettingsNotifier = controller;
  PageBackground.debugOverlayBuilder = (_) =>
      AuthTextureTunerOverlay(controller: controller);
  return controller;
}

void disableAuthTextureTuner() {
  PageBackground.debugSettingsNotifier = null;
  PageBackground.debugOverlayBuilder = null;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class AuthTextureTunerController extends ValueNotifier<AuthTextureSettings> {
  AuthTextureTunerController([super.initial = AuthTextureSettings.defaults]);

  AuthTextureSettings get settings => value;

  void setField(AuthTextureField field, double newValue) {
    value = field.updateSettings(value, newValue);
  }

  void reset() {
    value = AuthTextureSettings.defaults;
  }
}

// ---------------------------------------------------------------------------
// Field enum & metadata
// ---------------------------------------------------------------------------

enum AuthTextureField {
  grainSpacing,
  grainLimitYFactor,
  grainNoiseThreshold,
  grainOpacityScale,
  grainMinRadius,
  grainMaxRadiusDelta,
  grainColorLerpScale,
  grainFadeCenterX,
  grainFadeCenterY,
  grainFadeRadius,
  halftoneSpacing,
  halftoneStartYFactor,
  halftoneBaseRadius,
  halftoneRadiusGrowth,
  halftoneOpacityBase,
  halftoneOpacityGrowth,
  halftoneColorLerpScale,
  halftoneConvexCurveDepthFactor,
  halftoneLandscapeCurveBoost,
  halftoneCurveExponent,
  halftoneLandscapeExponentPull,
}

const List<AuthTextureField> _grainFields = [
  AuthTextureField.grainSpacing,
  AuthTextureField.grainLimitYFactor,
  AuthTextureField.grainNoiseThreshold,
  AuthTextureField.grainOpacityScale,
  AuthTextureField.grainMinRadius,
  AuthTextureField.grainMaxRadiusDelta,
  AuthTextureField.grainColorLerpScale,
  AuthTextureField.grainFadeCenterX,
  AuthTextureField.grainFadeCenterY,
  AuthTextureField.grainFadeRadius,
];

const List<AuthTextureField> _halftoneFields = [
  AuthTextureField.halftoneSpacing,
  AuthTextureField.halftoneStartYFactor,
  AuthTextureField.halftoneBaseRadius,
  AuthTextureField.halftoneRadiusGrowth,
  AuthTextureField.halftoneOpacityBase,
  AuthTextureField.halftoneOpacityGrowth,
  AuthTextureField.halftoneColorLerpScale,
  AuthTextureField.halftoneConvexCurveDepthFactor,
  AuthTextureField.halftoneLandscapeCurveBoost,
  AuthTextureField.halftoneCurveExponent,
  AuthTextureField.halftoneLandscapeExponentPull,
];

extension AuthTextureFieldMetadata on AuthTextureField {
  String get label {
    switch (this) {
      case AuthTextureField.grainSpacing:
        return 'Spacing';
      case AuthTextureField.grainLimitYFactor:
        return 'Limit Y Factor';
      case AuthTextureField.grainNoiseThreshold:
        return 'Noise Threshold';
      case AuthTextureField.grainOpacityScale:
        return 'Opacity Scale';
      case AuthTextureField.grainMinRadius:
        return 'Min Radius';
      case AuthTextureField.grainMaxRadiusDelta:
        return 'Max Radius Delta';
      case AuthTextureField.grainColorLerpScale:
        return 'Color Lerp Scale';
      case AuthTextureField.grainFadeCenterX:
        return 'Fade Center X';
      case AuthTextureField.grainFadeCenterY:
        return 'Fade Center Y';
      case AuthTextureField.grainFadeRadius:
        return 'Fade Radius';
      case AuthTextureField.halftoneSpacing:
        return 'Spacing';
      case AuthTextureField.halftoneStartYFactor:
        return 'Start Y Factor';
      case AuthTextureField.halftoneBaseRadius:
        return 'Base Radius';
      case AuthTextureField.halftoneRadiusGrowth:
        return 'Radius Growth';
      case AuthTextureField.halftoneOpacityBase:
        return 'Opacity Base';
      case AuthTextureField.halftoneOpacityGrowth:
        return 'Opacity Growth';
      case AuthTextureField.halftoneColorLerpScale:
        return 'Color Lerp Scale';
      case AuthTextureField.halftoneConvexCurveDepthFactor:
        return 'Curve Depth Factor';
      case AuthTextureField.halftoneLandscapeCurveBoost:
        return 'Landscape Curve Boost';
      case AuthTextureField.halftoneCurveExponent:
        return 'Curve Exponent';
      case AuthTextureField.halftoneLandscapeExponentPull:
        return 'Landscape Exponent Pull';
    }
  }

  double get min {
    switch (this) {
      case AuthTextureField.grainSpacing:
        return 0.5;
      case AuthTextureField.grainLimitYFactor:
      case AuthTextureField.grainNoiseThreshold:
      case AuthTextureField.grainOpacityScale:
      case AuthTextureField.grainMinRadius:
      case AuthTextureField.grainMaxRadiusDelta:
      case AuthTextureField.grainColorLerpScale:
        return 0.0;
      case AuthTextureField.grainFadeCenterX:
        return -1.0;
      case AuthTextureField.grainFadeCenterY:
        return -1.5;
      case AuthTextureField.grainFadeRadius:
        return 0.1;
      case AuthTextureField.halftoneSpacing:
        return 4.0;
      case AuthTextureField.halftoneStartYFactor:
      case AuthTextureField.halftoneBaseRadius:
      case AuthTextureField.halftoneRadiusGrowth:
      case AuthTextureField.halftoneOpacityBase:
      case AuthTextureField.halftoneOpacityGrowth:
      case AuthTextureField.halftoneColorLerpScale:
      case AuthTextureField.halftoneConvexCurveDepthFactor:
      case AuthTextureField.halftoneLandscapeCurveBoost:
        return 0.0;
      case AuthTextureField.halftoneCurveExponent:
        return 0.5;
      case AuthTextureField.halftoneLandscapeExponentPull:
        return 0.0;
    }
  }

  double get max {
    switch (this) {
      case AuthTextureField.grainSpacing:
        return 6.0;
      case AuthTextureField.grainLimitYFactor:
        return 1.2;
      case AuthTextureField.grainNoiseThreshold:
        return 0.5;
      case AuthTextureField.grainOpacityScale:
        return 1.5;
      case AuthTextureField.grainMinRadius:
        return 1.5;
      case AuthTextureField.grainMaxRadiusDelta:
        return 2.0;
      case AuthTextureField.grainColorLerpScale:
        return 1.5;
      case AuthTextureField.grainFadeCenterX:
        return 1.0;
      case AuthTextureField.grainFadeCenterY:
        return 1.0;
      case AuthTextureField.grainFadeRadius:
        return 6.0;
      case AuthTextureField.halftoneSpacing:
        return 28.0;
      case AuthTextureField.halftoneStartYFactor:
        return 1.0;
      case AuthTextureField.halftoneBaseRadius:
        return 3.0;
      case AuthTextureField.halftoneRadiusGrowth:
        return 30.0;
      case AuthTextureField.halftoneOpacityBase:
        return 1.0;
      case AuthTextureField.halftoneOpacityGrowth:
        return 1.0;
      case AuthTextureField.halftoneColorLerpScale:
        return 1.5;
      case AuthTextureField.halftoneConvexCurveDepthFactor:
        return 0.5;
      case AuthTextureField.halftoneLandscapeCurveBoost:
        return 3.0;
      case AuthTextureField.halftoneCurveExponent:
        return 4.0;
      case AuthTextureField.halftoneLandscapeExponentPull:
        return 2.0;
    }
  }

  double get step {
    switch (this) {
      case AuthTextureField.grainSpacing:
        return 0.1;
      case AuthTextureField.grainLimitYFactor:
      case AuthTextureField.grainNoiseThreshold:
      case AuthTextureField.grainOpacityScale:
      case AuthTextureField.grainMinRadius:
      case AuthTextureField.grainMaxRadiusDelta:
      case AuthTextureField.grainColorLerpScale:
      case AuthTextureField.grainFadeCenterX:
      case AuthTextureField.grainFadeCenterY:
      case AuthTextureField.grainFadeRadius:
      case AuthTextureField.halftoneStartYFactor:
      case AuthTextureField.halftoneBaseRadius:
      case AuthTextureField.halftoneOpacityBase:
      case AuthTextureField.halftoneOpacityGrowth:
      case AuthTextureField.halftoneColorLerpScale:
      case AuthTextureField.halftoneConvexCurveDepthFactor:
      case AuthTextureField.halftoneLandscapeCurveBoost:
      case AuthTextureField.halftoneCurveExponent:
      case AuthTextureField.halftoneLandscapeExponentPull:
        return 0.01;
      case AuthTextureField.halftoneSpacing:
        return 1.0;
      case AuthTextureField.halftoneRadiusGrowth:
        return 0.1;
    }
  }

  int get divisions => ((max - min) / step).round();

  double valueOf(AuthTextureSettings settings) {
    switch (this) {
      case AuthTextureField.grainSpacing:
        return settings.grainSpacing;
      case AuthTextureField.grainLimitYFactor:
        return settings.grainLimitYFactor;
      case AuthTextureField.grainNoiseThreshold:
        return settings.grainNoiseThreshold;
      case AuthTextureField.grainOpacityScale:
        return settings.grainOpacityScale;
      case AuthTextureField.grainMinRadius:
        return settings.grainMinRadius;
      case AuthTextureField.grainMaxRadiusDelta:
        return settings.grainMaxRadiusDelta;
      case AuthTextureField.grainColorLerpScale:
        return settings.grainColorLerpScale;
      case AuthTextureField.grainFadeCenterX:
        return settings.grainFadeCenterX;
      case AuthTextureField.grainFadeCenterY:
        return settings.grainFadeCenterY;
      case AuthTextureField.grainFadeRadius:
        return settings.grainFadeRadius;
      case AuthTextureField.halftoneSpacing:
        return settings.halftoneSpacing;
      case AuthTextureField.halftoneStartYFactor:
        return settings.halftoneStartYFactor;
      case AuthTextureField.halftoneBaseRadius:
        return settings.halftoneBaseRadius;
      case AuthTextureField.halftoneRadiusGrowth:
        return settings.halftoneRadiusGrowth;
      case AuthTextureField.halftoneOpacityBase:
        return settings.halftoneOpacityBase;
      case AuthTextureField.halftoneOpacityGrowth:
        return settings.halftoneOpacityGrowth;
      case AuthTextureField.halftoneColorLerpScale:
        return settings.halftoneColorLerpScale;
      case AuthTextureField.halftoneConvexCurveDepthFactor:
        return settings.halftoneConvexCurveDepthFactor;
      case AuthTextureField.halftoneLandscapeCurveBoost:
        return settings.halftoneLandscapeCurveBoost;
      case AuthTextureField.halftoneCurveExponent:
        return settings.halftoneCurveExponent;
      case AuthTextureField.halftoneLandscapeExponentPull:
        return settings.halftoneLandscapeExponentPull;
    }
  }

  AuthTextureSettings updateSettings(
    AuthTextureSettings settings,
    double value,
  ) {
    switch (this) {
      case AuthTextureField.grainSpacing:
        return settings.copyWith(grainSpacing: value);
      case AuthTextureField.grainLimitYFactor:
        return settings.copyWith(grainLimitYFactor: value);
      case AuthTextureField.grainNoiseThreshold:
        return settings.copyWith(grainNoiseThreshold: value);
      case AuthTextureField.grainOpacityScale:
        return settings.copyWith(grainOpacityScale: value);
      case AuthTextureField.grainMinRadius:
        return settings.copyWith(grainMinRadius: value);
      case AuthTextureField.grainMaxRadiusDelta:
        return settings.copyWith(grainMaxRadiusDelta: value);
      case AuthTextureField.grainColorLerpScale:
        return settings.copyWith(grainColorLerpScale: value);
      case AuthTextureField.grainFadeCenterX:
        return settings.copyWith(grainFadeCenterX: value);
      case AuthTextureField.grainFadeCenterY:
        return settings.copyWith(grainFadeCenterY: value);
      case AuthTextureField.grainFadeRadius:
        return settings.copyWith(grainFadeRadius: value);
      case AuthTextureField.halftoneSpacing:
        return settings.copyWith(halftoneSpacing: value);
      case AuthTextureField.halftoneStartYFactor:
        return settings.copyWith(halftoneStartYFactor: value);
      case AuthTextureField.halftoneBaseRadius:
        return settings.copyWith(halftoneBaseRadius: value);
      case AuthTextureField.halftoneRadiusGrowth:
        return settings.copyWith(halftoneRadiusGrowth: value);
      case AuthTextureField.halftoneOpacityBase:
        return settings.copyWith(halftoneOpacityBase: value);
      case AuthTextureField.halftoneOpacityGrowth:
        return settings.copyWith(halftoneOpacityGrowth: value);
      case AuthTextureField.halftoneColorLerpScale:
        return settings.copyWith(halftoneColorLerpScale: value);
      case AuthTextureField.halftoneConvexCurveDepthFactor:
        return settings.copyWith(halftoneConvexCurveDepthFactor: value);
      case AuthTextureField.halftoneLandscapeCurveBoost:
        return settings.copyWith(halftoneLandscapeCurveBoost: value);
      case AuthTextureField.halftoneCurveExponent:
        return settings.copyWith(halftoneCurveExponent: value);
      case AuthTextureField.halftoneLandscapeExponentPull:
        return settings.copyWith(halftoneLandscapeExponentPull: value);
    }
  }

  String formattedValue(AuthTextureSettings settings) {
    return _formatDouble(valueOf(settings));
  }
}

// ---------------------------------------------------------------------------
// Snippet generation (debug-only extension on AuthTextureSettings)
// ---------------------------------------------------------------------------

extension AuthTextureSettingsSnippet on AuthTextureSettings {
  String toDartSnippet() {
    final buffer = StringBuffer()
      ..writeln('static const _GrainOp grain = _GrainOp(')
      ..writeln('  spacing: ${_formatDouble(grainSpacing)},')
      ..writeln('  limitYFactor: ${_formatDouble(grainLimitYFactor)},')
      ..writeln('  noiseThreshold: ${_formatDouble(grainNoiseThreshold)},')
      ..writeln('  opacityScale: ${_formatDouble(grainOpacityScale)},')
      ..writeln('  minRadius: ${_formatDouble(grainMinRadius)},')
      ..writeln('  maxRadiusDelta: ${_formatDouble(grainMaxRadiusDelta)},')
      ..writeln('  fromColor: AuthPalette.grainFrom,')
      ..writeln('  toColor: AuthPalette.grainTo,')
      ..writeln('  colorLerpScale: ${_formatDouble(grainColorLerpScale)},')
      ..writeln(
        '  fadeCenter: Alignment(${_formatDouble(grainFadeCenterX)}, ${_formatDouble(grainFadeCenterY)}),',
      )
      ..writeln('  fadeRadius: ${_formatDouble(grainFadeRadius)},')
      ..writeln(');')
      ..writeln()
      ..writeln('static const _HalftoneOp halftone = _HalftoneOp(')
      ..writeln('  spacing: ${_formatDouble(halftoneSpacing)},')
      ..writeln('  startYFactor: ${_formatDouble(halftoneStartYFactor)},')
      ..writeln('  baseRadius: ${_formatDouble(halftoneBaseRadius)},')
      ..writeln('  radiusGrowth: ${_formatDouble(halftoneRadiusGrowth)},')
      ..writeln('  opacityBase: ${_formatDouble(halftoneOpacityBase)},')
      ..writeln('  opacityGrowth: ${_formatDouble(halftoneOpacityGrowth)},')
      ..writeln('  topColor: AuthPalette.halftoneTop,')
      ..writeln('  bottomColor: AuthPalette.halftoneBottom,')
      ..writeln('  colorLerpScale: ${_formatDouble(halftoneColorLerpScale)},')
      ..writeln(
        '  convexCurveDepthFactor: ${_formatDouble(halftoneConvexCurveDepthFactor)},',
      )
      ..writeln(
        '  landscapeCurveBoost: ${_formatDouble(halftoneLandscapeCurveBoost)},',
      )
      ..writeln('  curveExponent: ${_formatDouble(halftoneCurveExponent)},')
      ..writeln(
        '  landscapeExponentPull: ${_formatDouble(halftoneLandscapeExponentPull)},',
      )
      ..writeln(');');

    return buffer.toString().trimRight();
  }
}

// ---------------------------------------------------------------------------
// Tuner overlay widgets
// ---------------------------------------------------------------------------

class AuthTextureTunerOverlay extends StatefulWidget {
  final AuthTextureTunerController controller;

  const AuthTextureTunerOverlay({super.key, required this.controller});

  @override
  State<AuthTextureTunerOverlay> createState() =>
      _AuthTextureTunerOverlayState();
}

class _AuthTextureTunerOverlayState extends State<AuthTextureTunerOverlay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SizedBox(
            width: double.infinity,
            child: _isExpanded ? _buildPanel(context) : _buildLauncher(context),
          ),
        ),
      ),
    );
  }

  Widget _buildLauncher(BuildContext context) {
    return _DebugGlassContainer(
      child: InkWell(
        key: const Key('authTextureTunerLauncher'),
        onTap: () {
          setState(() {
            _isExpanded = true;
          });
        },
        borderRadius: BorderRadius.circular(AuthPalette.glassRadius),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Tune',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final controller = widget.controller;

    return _DebugGlassContainer(
      child: ValueListenableBuilder<AuthTextureSettings>(
        valueListenable: controller,
        builder: (context, settings, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const Key('authTextureTunerPanel'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Auth Texture Tuner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close tuner',
                      onPressed: () {
                        setState(() {
                          _isExpanded = false;
                        });
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Debug-only live controls for the auth background texture.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('authTextureResetButton'),
                      onPressed: controller.reset,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reset'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('authTextureCopyButton'),
                      onPressed: () => _copyValues(context, settings),
                      icon: const Icon(Icons.content_copy_rounded),
                      label: const Text('Copy values'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TextureFieldSection(
                  title: 'Grain',
                  fields: _grainFields,
                  settings: settings,
                  controller: controller,
                ),
                const SizedBox(height: 16),
                _TextureFieldSection(
                  title: 'Halftone',
                  fields: _halftoneFields,
                  settings: settings,
                  controller: controller,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyValues(
    BuildContext context,
    AuthTextureSettings settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: settings.toDartSnippet()));
    if (!mounted) {
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Copied auth texture snippet to clipboard.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TextureFieldSection extends StatelessWidget {
  final String title;
  final List<AuthTextureField> fields;
  final AuthTextureSettings settings;
  final AuthTextureTunerController controller;

  const _TextureFieldSection({
    required this.title,
    required this.fields,
    required this.settings,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final field in fields) ...[
          _TextureFieldSlider(
            field: field,
            settings: settings,
            controller: controller,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TextureFieldSlider extends StatelessWidget {
  final AuthTextureField field;
  final AuthTextureSettings settings;
  final AuthTextureTunerController controller;

  const _TextureFieldSlider({
    required this.field,
    required this.settings,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final value = field.valueOf(settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                field.label,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            Text(
              field.formattedValue(settings),
              style: const TextStyle(
                color: Colors.white70,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          key: Key('authTextureField-${field.name}'),
          value: value,
          min: field.min,
          max: field.max,
          divisions: field.divisions,
          label: field.formattedValue(settings),
          onChanged: (nextValue) {
            controller.setField(field, nextValue);
          },
        ),
      ],
    );
  }
}

class _DebugGlassContainer extends StatelessWidget {
  final Widget child;

  const _DebugGlassContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AuthPalette.glassRadius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: AuthPalette.panelShadow,
            blurRadius: AuthPalette.glassShadowBlur,
            offset: Offset(0, AuthPalette.glassShadowOffsetY),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: AuthPalette.glassBlurSigma,
            sigmaY: AuthPalette.glassBlurSigma,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AuthPalette.panel.withValues(
                alpha: AuthPalette.panelAlpha,
              ),
              borderRadius: radius,
              border: Border.all(color: AuthPalette.panelBorder),
            ),
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatDouble(double value) {
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}
