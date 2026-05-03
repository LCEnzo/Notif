import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/notif_tokens.dart';

// ---------------------------------------------------------------------------
// Texture settings (production data class)
// ---------------------------------------------------------------------------

@immutable
class AuthTextureSettings {
  final double grainSpacing;
  final double grainLimitYFactor;
  final double grainNoiseThreshold;
  final double grainOpacityScale;
  final double grainMinRadius;
  final double grainMaxRadiusDelta;
  final double grainColorLerpScale;
  final double grainFadeCenterX;
  final double grainFadeCenterY;
  final double grainFadeRadius;
  final double halftoneSpacing;
  final double halftoneStartYFactor;
  final double halftoneBaseRadius;
  final double halftoneRadiusGrowth;
  final double halftoneOpacityBase;
  final double halftoneOpacityGrowth;
  final double halftoneColorLerpScale;
  final double halftoneConvexCurveDepthFactor;
  final double halftoneLandscapeCurveBoost;
  final double halftoneCurveExponent;
  final double halftoneLandscapeExponentPull;

  const AuthTextureSettings({
    required this.grainSpacing,
    required this.grainLimitYFactor,
    required this.grainNoiseThreshold,
    required this.grainOpacityScale,
    required this.grainMinRadius,
    required this.grainMaxRadiusDelta,
    required this.grainColorLerpScale,
    required this.grainFadeCenterX,
    required this.grainFadeCenterY,
    required this.grainFadeRadius,
    required this.halftoneSpacing,
    required this.halftoneStartYFactor,
    required this.halftoneBaseRadius,
    required this.halftoneRadiusGrowth,
    required this.halftoneOpacityBase,
    required this.halftoneOpacityGrowth,
    required this.halftoneColorLerpScale,
    required this.halftoneConvexCurveDepthFactor,
    required this.halftoneLandscapeCurveBoost,
    required this.halftoneCurveExponent,
    required this.halftoneLandscapeExponentPull,
  });

  static const AuthTextureSettings defaults = AuthTextureSettings(
    grainSpacing: 4.0,
    grainLimitYFactor: 1.2,
    grainNoiseThreshold: 0.41,
    grainOpacityScale: 0.49,
    grainMinRadius: 0.14,
    grainMaxRadiusDelta: 0.9,
    grainColorLerpScale: 1.5,
    grainFadeCenterX: -0.02,
    grainFadeCenterY: -0.54,
    grainFadeRadius: 1.58,
    halftoneSpacing: 11.0,
    halftoneStartYFactor: 0.43,
    halftoneBaseRadius: 0.93,
    halftoneRadiusGrowth: 13.2,
    halftoneOpacityBase: 0.45,
    halftoneOpacityGrowth: 0.3,
    halftoneColorLerpScale: 0.7,
    halftoneConvexCurveDepthFactor: 0.13,
    halftoneLandscapeCurveBoost: 1.73,
    halftoneCurveExponent: 1.86,
    halftoneLandscapeExponentPull: 0.48,
  );

  AuthTextureSettings copyWith({
    double? grainSpacing,
    double? grainLimitYFactor,
    double? grainNoiseThreshold,
    double? grainOpacityScale,
    double? grainMinRadius,
    double? grainMaxRadiusDelta,
    double? grainColorLerpScale,
    double? grainFadeCenterX,
    double? grainFadeCenterY,
    double? grainFadeRadius,
    double? halftoneSpacing,
    double? halftoneStartYFactor,
    double? halftoneBaseRadius,
    double? halftoneRadiusGrowth,
    double? halftoneOpacityBase,
    double? halftoneOpacityGrowth,
    double? halftoneColorLerpScale,
    double? halftoneConvexCurveDepthFactor,
    double? halftoneLandscapeCurveBoost,
    double? halftoneCurveExponent,
    double? halftoneLandscapeExponentPull,
  }) {
    return AuthTextureSettings(
      grainSpacing: grainSpacing ?? this.grainSpacing,
      grainLimitYFactor: grainLimitYFactor ?? this.grainLimitYFactor,
      grainNoiseThreshold: grainNoiseThreshold ?? this.grainNoiseThreshold,
      grainOpacityScale: grainOpacityScale ?? this.grainOpacityScale,
      grainMinRadius: grainMinRadius ?? this.grainMinRadius,
      grainMaxRadiusDelta: grainMaxRadiusDelta ?? this.grainMaxRadiusDelta,
      grainColorLerpScale: grainColorLerpScale ?? this.grainColorLerpScale,
      grainFadeCenterX: grainFadeCenterX ?? this.grainFadeCenterX,
      grainFadeCenterY: grainFadeCenterY ?? this.grainFadeCenterY,
      grainFadeRadius: grainFadeRadius ?? this.grainFadeRadius,
      halftoneSpacing: halftoneSpacing ?? this.halftoneSpacing,
      halftoneStartYFactor: halftoneStartYFactor ?? this.halftoneStartYFactor,
      halftoneBaseRadius: halftoneBaseRadius ?? this.halftoneBaseRadius,
      halftoneRadiusGrowth: halftoneRadiusGrowth ?? this.halftoneRadiusGrowth,
      halftoneOpacityBase: halftoneOpacityBase ?? this.halftoneOpacityBase,
      halftoneOpacityGrowth:
          halftoneOpacityGrowth ?? this.halftoneOpacityGrowth,
      halftoneColorLerpScale:
          halftoneColorLerpScale ?? this.halftoneColorLerpScale,
      halftoneConvexCurveDepthFactor: halftoneConvexCurveDepthFactor ??
          this.halftoneConvexCurveDepthFactor,
      halftoneLandscapeCurveBoost:
          halftoneLandscapeCurveBoost ?? this.halftoneLandscapeCurveBoost,
      halftoneCurveExponent:
          halftoneCurveExponent ?? this.halftoneCurveExponent,
      halftoneLandscapeExponentPull: halftoneLandscapeExponentPull ??
          this.halftoneLandscapeExponentPull,
    );
  }

  _GrainOp _toGrainOp(_AuthBackdropPalette palette) {
    return _GrainOp(
      spacing: grainSpacing,
      limitYFactor: grainLimitYFactor,
      noiseThreshold: grainNoiseThreshold,
      opacityScale: grainOpacityScale,
      minRadius: grainMinRadius,
      maxRadiusDelta: grainMaxRadiusDelta,
      fromColor: palette.grainFrom,
      toColor: palette.grainTo,
      colorLerpScale: grainColorLerpScale,
      fadeCenter: Alignment(grainFadeCenterX, grainFadeCenterY),
      fadeRadius: grainFadeRadius,
    );
  }

  _HalftoneOp _toHalftoneOp(_AuthBackdropPalette palette) {
    return _HalftoneOp(
      spacing: halftoneSpacing,
      startYFactor: halftoneStartYFactor,
      baseRadius: halftoneBaseRadius,
      radiusGrowth: halftoneRadiusGrowth,
      opacityBase: halftoneOpacityBase,
      opacityGrowth: halftoneOpacityGrowth,
      topColor: palette.halftoneTop,
      bottomColor: palette.halftoneBottom,
      colorLerpScale: halftoneColorLerpScale,
      convexCurveDepthFactor: halftoneConvexCurveDepthFactor,
      landscapeCurveBoost: halftoneLandscapeCurveBoost,
      curveExponent: halftoneCurveExponent,
      landscapeExponentPull: halftoneLandscapeExponentPull,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AuthTextureSettings &&
            other.grainSpacing == grainSpacing &&
            other.grainLimitYFactor == grainLimitYFactor &&
            other.grainNoiseThreshold == grainNoiseThreshold &&
            other.grainOpacityScale == grainOpacityScale &&
            other.grainMinRadius == grainMinRadius &&
            other.grainMaxRadiusDelta == grainMaxRadiusDelta &&
            other.grainColorLerpScale == grainColorLerpScale &&
            other.grainFadeCenterX == grainFadeCenterX &&
            other.grainFadeCenterY == grainFadeCenterY &&
            other.grainFadeRadius == grainFadeRadius &&
            other.halftoneSpacing == halftoneSpacing &&
            other.halftoneStartYFactor == halftoneStartYFactor &&
            other.halftoneBaseRadius == halftoneBaseRadius &&
            other.halftoneRadiusGrowth == halftoneRadiusGrowth &&
            other.halftoneOpacityBase == halftoneOpacityBase &&
            other.halftoneOpacityGrowth == halftoneOpacityGrowth &&
            other.halftoneColorLerpScale == halftoneColorLerpScale &&
            other.halftoneConvexCurveDepthFactor ==
                halftoneConvexCurveDepthFactor &&
            other.halftoneLandscapeCurveBoost == halftoneLandscapeCurveBoost &&
            other.halftoneCurveExponent == halftoneCurveExponent &&
            other.halftoneLandscapeExponentPull ==
                halftoneLandscapeExponentPull;
  }

  @override
  int get hashCode {
    return Object.hashAll([
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
    ]);
  }
}

@immutable
class _AuthBackdropPalette {
  final List<Color> baseGradientColors;
  final List<double> baseGradientStops;
  final List<Color> bloomColors;
  final List<double> bloomStops;
  final List<Color> transitionColors;
  final List<double> transitionStops;
  final List<Color> floorFadeColors;
  final List<double> floorFadeStops;
  final Color grainFrom;
  final Color grainTo;
  final Color halftoneTop;
  final Color halftoneBottom;

  const _AuthBackdropPalette({
    required this.baseGradientColors,
    required this.baseGradientStops,
    required this.bloomColors,
    required this.bloomStops,
    required this.transitionColors,
    required this.transitionStops,
    required this.floorFadeColors,
    required this.floorFadeStops,
    required this.grainFrom,
    required this.grainTo,
    required this.halftoneTop,
    required this.halftoneBottom,
  });

  factory _AuthBackdropPalette.fromTokens(NotifTokens tokens) {
    final colors = tokens.authBackdrop;

    return _AuthBackdropPalette(
      baseGradientColors: colors.baseGradientColors,
      baseGradientStops: const [0.0, 0.3, 0.58, 0.82, 1.0],
      bloomColors: colors.bloomColors,
      bloomStops: const [0.0, 0.24, 0.52, 1.0],
      transitionColors: colors.transitionColors,
      transitionStops: const [0.22, 0.56, 0.82, 1.0],
      floorFadeColors: colors.floorFadeColors,
      floorFadeStops: const [0.72, 0.9, 1.0],
      grainFrom: colors.grainFrom,
      grainTo: colors.grainTo,
      halftoneTop: colors.halftoneTop,
      halftoneBottom: colors.halftoneBottom,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _AuthBackdropPalette &&
            listEquals(other.baseGradientColors, baseGradientColors) &&
            listEquals(other.baseGradientStops, baseGradientStops) &&
            listEquals(other.bloomColors, bloomColors) &&
            listEquals(other.bloomStops, bloomStops) &&
            listEquals(other.transitionColors, transitionColors) &&
            listEquals(other.transitionStops, transitionStops) &&
            listEquals(other.floorFadeColors, floorFadeColors) &&
            listEquals(other.floorFadeStops, floorFadeStops) &&
            other.grainFrom == grainFrom &&
            other.grainTo == grainTo &&
            other.halftoneTop == halftoneTop &&
            other.halftoneBottom == halftoneBottom;
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAll(baseGradientColors),
      Object.hashAll(baseGradientStops),
      Object.hashAll(bloomColors),
      Object.hashAll(bloomStops),
      Object.hashAll(transitionColors),
      Object.hashAll(transitionStops),
      Object.hashAll(floorFadeColors),
      Object.hashAll(floorFadeStops),
      grainFrom,
      grainTo,
      halftoneTop,
      halftoneBottom,
    );
  }
}

// ---------------------------------------------------------------------------
// Page background widget
// ---------------------------------------------------------------------------

class PageBackground extends StatelessWidget {
  /// Set by the debug tuner to receive live settings changes.
  /// Null in release builds — the texture layer uses [AuthTextureSettings.defaults].
  static ValueNotifier<AuthTextureSettings>? debugSettingsNotifier;

  /// Set by the debug tuner to inject the overlay widget.
  /// Null in release builds — no overlay is shown.
  static WidgetBuilder? debugOverlayBuilder;

  final Widget child;

  const PageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final notifier = debugSettingsNotifier;
    final tokens =
        Theme.of(context).extension<NotifTokens>() ??
        NotifTokens.build(NotifColorway.dusk1);
    final palette = _AuthBackdropPalette.fromTokens(tokens);
    final baseOperations = [
      _LinearGradientOp(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: palette.baseGradientColors,
        stops: palette.baseGradientStops,
        rect: const _RelativeRect.full(),
        shape: _BackgroundShape.rect,
      ),
      _CircularGradientOp(
        centerYFactor: -0.05,
        diameterFactor: 0.82,
        colors: palette.bloomColors,
        stops: palette.bloomStops,
      ),
      _LinearGradientOp(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: palette.transitionColors,
        stops: palette.transitionStops,
      ),
    ];
    final foregroundOperations = [
      _LinearGradientOp(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: palette.floorFadeColors,
        stops: palette.floorFadeStops,
      ),
    ];

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _PosterBackgroundPainter(baseOperations),
          ),
          if (notifier != null)
            ValueListenableBuilder<AuthTextureSettings>(
              valueListenable: notifier,
              builder: (context, settings, _) =>
                  _PosterTextureLayer(settings: settings, palette: palette),
            )
          else
            _PosterTextureLayer(
              settings: AuthTextureSettings.defaults,
              palette: palette,
            ),
          CustomPaint(
            painter: _PosterBackgroundPainter(foregroundOperations),
          ),
          child,
          if (debugOverlayBuilder != null)
            Builder(builder: debugOverlayBuilder!),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Texture layer (shader)
// ---------------------------------------------------------------------------

class _PosterTextureLayer extends StatelessWidget {
  static final Future<ui.FragmentProgram> _programFuture =
      ui.FragmentProgram.fromAsset('shaders/auth_texture.frag');

  final AuthTextureSettings settings;
  final _AuthBackdropPalette palette;

  const _PosterTextureLayer({required this.settings, required this.palette});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _programFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.expand();
        }
        final program = snapshot.data;
        if (program == null) {
          return const SizedBox.expand();
        }
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return CustomPaint(
          painter: _PosterTexturePainter(
            program: program,
            settings: settings,
            palette: palette,
            dpr: dpr,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Background painters
// ---------------------------------------------------------------------------

class _PosterBackgroundPainter extends CustomPainter {
  final List<_BackgroundOp> operations;

  const _PosterBackgroundPainter(this.operations);

  @override
  void paint(Canvas canvas, Size size) {
    for (final operation in operations) {
      operation.paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _PosterBackgroundPainter oldDelegate) {
    return !listEquals(oldDelegate.operations, operations);
  }
}

class _PosterTexturePainter extends CustomPainter {
  final ui.FragmentProgram program;
  final AuthTextureSettings settings;
  final _AuthBackdropPalette palette;
  final double dpr;

  const _PosterTexturePainter({
    required this.program,
    required this.settings,
    required this.palette,
    required this.dpr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grain = settings._toGrainOp(palette);
    final halftone = settings._toHalftoneOp(palette);
    final shader = program.fragmentShader();
    var index = 0;

    // uSize — logical pixels to match CustomPainter size
    shader.setFloat(index++, size.width);
    shader.setFloat(index++, size.height);

    // uPixelScale — kept at 1.0 (params are in logical pixel units)
    shader.setFloat(index++, 1.0);

    shader.setFloat(index++, grain.spacing);
    shader.setFloat(index++, grain.limitYFactor);
    shader.setFloat(index++, grain.noiseThreshold);
    shader.setFloat(index++, grain.opacityScale);
    shader.setFloat(index++, grain.minRadius);
    shader.setFloat(index++, grain.maxRadiusDelta);
    index = _setColorUniform(shader, index, grain.fromColor);
    index = _setColorUniform(shader, index, grain.toColor);
    shader.setFloat(index++, grain.colorLerpScale);
    shader.setFloat(index++, grain.fadeCenter.x);
    shader.setFloat(index++, grain.fadeCenter.y);
    shader.setFloat(index++, grain.fadeRadius);

    shader.setFloat(index++, halftone.spacing);
    shader.setFloat(index++, halftone.startYFactor);
    shader.setFloat(index++, halftone.baseRadius);
    shader.setFloat(index++, halftone.radiusGrowth);
    shader.setFloat(index++, halftone.opacityBase);
    shader.setFloat(index++, halftone.opacityGrowth);
    index = _setColorUniform(shader, index, halftone.topColor);
    index = _setColorUniform(shader, index, halftone.bottomColor);
    shader.setFloat(index++, halftone.colorLerpScale);
    shader.setFloat(index++, halftone.convexCurveDepthFactor);
    shader.setFloat(index++, halftone.landscapeCurveBoost);
    shader.setFloat(index++, halftone.curveExponent);
    shader.setFloat(index++, halftone.landscapeExponentPull);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _PosterTexturePainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.settings != settings ||
        oldDelegate.palette != palette ||
        oldDelegate.dpr != dpr;
  }
}

// ---------------------------------------------------------------------------
// Background operation helpers
// ---------------------------------------------------------------------------

int _setColorUniform(ui.FragmentShader shader, int index, Color color) {
  final argb = color.toARGB32();
  final alpha = ((argb >> 24) & 0xFF) / 255.0;
  final red = ((argb >> 16) & 0xFF) / 255.0;
  final green = ((argb >> 8) & 0xFF) / 255.0;
  final blue = (argb & 0xFF) / 255.0;

  shader.setFloat(index++, red);
  shader.setFloat(index++, green);
  shader.setFloat(index++, blue);
  shader.setFloat(index++, alpha);

  return index;
}

abstract class _BackgroundOp {
  const _BackgroundOp();

  void paint(Canvas canvas, Size size);
}

enum _BackgroundShape { rect, oval }

class _RelativeRect {
  final double leftFactor;
  final double topFactor;
  final double widthFactor;
  final double heightFactor;

  const _RelativeRect({
    required this.leftFactor,
    required this.topFactor,
    required this.widthFactor,
    required this.heightFactor,
  });

  const _RelativeRect.full()
      : leftFactor = 0,
        topFactor = 0,
        widthFactor = 1,
        heightFactor = 1;

  Rect resolve(Size size) {
    return Rect.fromLTWH(
      size.width * leftFactor,
      size.height * topFactor,
      size.width * widthFactor,
      size.height * heightFactor,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _RelativeRect &&
            other.leftFactor == leftFactor &&
            other.topFactor == topFactor &&
            other.widthFactor == widthFactor &&
            other.heightFactor == heightFactor;
  }

  @override
  int get hashCode => Object.hash(
        leftFactor,
        topFactor,
        widthFactor,
        heightFactor,
      );
}

class _LinearGradientOp extends _BackgroundOp {
  final Alignment begin;
  final Alignment end;
  final List<Color> colors;
  final List<double>? stops;
  final _RelativeRect rect;
  final _BackgroundShape shape;

  const _LinearGradientOp({
    required this.begin,
    required this.end,
    required this.colors,
    this.stops,
    this.rect = const _RelativeRect.full(),
    this.shape = _BackgroundShape.rect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final targetRect = rect.resolve(size);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: colors,
        stops: stops,
      ).createShader(targetRect);

    _drawShape(canvas, targetRect, paint, shape);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _LinearGradientOp &&
            other.begin == begin &&
            other.end == end &&
            listEquals(other.colors, colors) &&
            listEquals(other.stops, stops) &&
            other.rect == rect &&
            other.shape == shape;
  }

  @override
  int get hashCode => Object.hash(
        begin,
        end,
        Object.hashAll(colors),
        stops == null ? null : Object.hashAll(stops!),
        rect,
        shape,
      );
}

class _CircularGradientOp extends _BackgroundOp {
  final double centerYFactor;
  final double diameterFactor;
  final List<Color> colors;
  final List<double>? stops;

  const _CircularGradientOp({
    required this.centerYFactor,
    required this.diameterFactor,
    required this.colors,
    this.stops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * diameterFactor / 2;
    final center = Offset(size.width / 2, size.height * centerYFactor);
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1,
        colors: colors,
        stops: stops,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _CircularGradientOp &&
            other.centerYFactor == centerYFactor &&
            other.diameterFactor == diameterFactor &&
            listEquals(other.colors, colors) &&
            listEquals(other.stops, stops);
  }

  @override
  int get hashCode => Object.hash(
        centerYFactor,
        diameterFactor,
        Object.hashAll(colors),
        stops == null ? null : Object.hashAll(stops!),
      );
}

class _GrainOp {
  final double spacing;
  final double limitYFactor;
  final double noiseThreshold;
  final double opacityScale;
  final double minRadius;
  final double maxRadiusDelta;
  final Color fromColor;
  final Color toColor;
  final double colorLerpScale;
  final Alignment fadeCenter;
  final double fadeRadius;

  const _GrainOp({
    required this.spacing,
    required this.limitYFactor,
    required this.noiseThreshold,
    required this.opacityScale,
    required this.minRadius,
    required this.maxRadiusDelta,
    required this.fromColor,
    required this.toColor,
    required this.colorLerpScale,
    required this.fadeCenter,
    required this.fadeRadius,
  });
}

class _HalftoneOp {
  final double spacing;
  final double startYFactor;
  final double baseRadius;
  final double radiusGrowth;
  final double opacityBase;
  final double opacityGrowth;
  final Color topColor;
  final Color bottomColor;
  final double colorLerpScale;
  final double convexCurveDepthFactor;
  final double landscapeCurveBoost;
  final double curveExponent;
  final double landscapeExponentPull;

  const _HalftoneOp({
    required this.spacing,
    required this.startYFactor,
    required this.baseRadius,
    required this.radiusGrowth,
    required this.opacityBase,
    required this.opacityGrowth,
    required this.topColor,
    required this.bottomColor,
    required this.colorLerpScale,
    this.convexCurveDepthFactor = 0,
    this.landscapeCurveBoost = 0,
    this.curveExponent = 2,
    this.landscapeExponentPull = 0,
  });
}

void _drawShape(
  Canvas canvas,
  Rect rect,
  Paint paint,
  _BackgroundShape shape,
) {
  if (shape == _BackgroundShape.oval) {
    canvas.drawOval(rect, paint);
    return;
  }

  canvas.drawRect(rect, paint);
}
