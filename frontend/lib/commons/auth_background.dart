import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';

class PageBackground extends StatelessWidget {
  final Widget child;

  const PageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(
            painter: _PosterBackgroundPainter(
              _PosterBackgroundPainter.baseOperations,
            ),
          ),
          const _PosterTextureLayer(
            grain: _PosterBackgroundPainter.grain,
            halftone: _PosterBackgroundPainter.halftone,
          ),
          const CustomPaint(
            painter: _PosterBackgroundPainter(
              _PosterBackgroundPainter.foregroundOperations,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _PosterTextureLayer extends StatelessWidget {
  static final Future<ui.FragmentProgram> _programFuture =
      ui.FragmentProgram.fromAsset('shaders/auth_texture.frag');

  final _GrainOp grain;
  final _HalftoneOp halftone;

  const _PosterTextureLayer({
    required this.grain,
    required this.halftone,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _programFuture,
      builder: (context, snapshot) {
        final program = snapshot.data;
        if (program == null) {
          return const SizedBox.expand();
        }

        return CustomPaint(
          painter: _PosterTexturePainter(
            program: program,
            grain: grain,
            halftone: halftone,
          ),
        );
      },
    );
  }
}

class _PosterBackgroundPainter extends CustomPainter {
  static const List<_BackgroundOp> baseOperations = [
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.baseGradientColors,
      stops: AuthPalette.baseGradientStops,
      rect: _RelativeRect.full(),
      shape: _BackgroundShape.rect,
    ),
    _CircularGradientOp(
      centerYFactor: -0.05,
      diameterFactor: 0.82,
      colors: AuthPalette.bloomColors,
      stops: AuthPalette.bloomStops,
    ),
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.transitionColors,
      stops: AuthPalette.transitionStops,
    ),
  ];

  static const _GrainOp grain = _GrainOp(
    spacing: 2.0,
    limitYFactor: 1.0,
    noiseThreshold: 0.02, 
    opacityScale: 1.8,
    minRadius: 0.8, 
    maxRadiusDelta: 0.6,
    fromColor: AuthPalette.grainFrom,
    toColor: AuthPalette.grainTo,
    colorLerpScale: 1.0,
    fadeCenter: Alignment(0, -1),
    fadeRadius: 4.0, 
  );

  static const _HalftoneOp halftone = _HalftoneOp(
    spacing: 13,
    startYFactor: 0.42,
    baseRadius: 0.6,
    radiusGrowth: 12,
    opacityBase: 0.16,
    opacityGrowth: 0.26,
    topColor: AuthPalette.halftoneTop,
    bottomColor: AuthPalette.halftoneBottom,
    colorLerpScale: 0.66,
    convexCurveDepthFactor: 0.12,
    landscapeCurveBoost: 1.15,
    curveExponent: 1.7,
    landscapeExponentPull: 0.35,
  );

  static const List<_BackgroundOp> foregroundOperations = [
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.floorFadeColors,
      stops: AuthPalette.floorFadeStops,
    ),
  ];

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
    return !identical(oldDelegate.operations, operations);
  }
}

class _PosterTexturePainter extends CustomPainter {
  final ui.FragmentProgram program;
  final _GrainOp grain;
  final _HalftoneOp halftone;

  const _PosterTexturePainter({
    required this.program,
    required this.grain,
    required this.halftone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    var index = 0;

    shader.setFloat(index++, size.width);
    shader.setFloat(index++, size.height);

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
        !identical(oldDelegate.grain, grain) ||
        !identical(oldDelegate.halftone, halftone);
  }
}

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

/// Defines a shader target rectangle as fractions of the painted canvas.
class _RelativeRect {
  /// Left edge as a fraction of the canvas width.
  final double leftFactor;

  /// Top edge as a fraction of the canvas height.
  final double topFactor;

  /// Width as a fraction of the canvas width.
  final double widthFactor;

  /// Height as a fraction of the canvas height.
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
}

/// Paints a linear gradient into a rectangular or oval region.
class _LinearGradientOp extends _BackgroundOp {
  /// Gradient start in Flutter's alignment space, e.g. `topCenter`.
  final Alignment begin;

  /// Gradient end in Flutter's alignment space.
  final Alignment end;

  /// Colors sampled across the gradient from [begin] to [end].
  final List<Color> colors;

  /// Optional normalized stop positions for [colors].
  final List<double>? stops;

  /// Region of the canvas that the shader is created against.
  final _RelativeRect rect;

  /// Shape used when drawing the gradient-filled [rect].
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
}

/// Paints a radial bloom whose size and vertical placement scale with the page.
class _CircularGradientOp extends _BackgroundOp {
  /// Vertical center as a fraction of canvas height.
  /// `0` places the bloom center on the top edge, `0.5` in the middle.
  final double centerYFactor;

  /// Circle diameter as a fraction of canvas width.
  final double diameterFactor;

  /// Colors sampled from the middle of the bloom outward.
  final List<Color> colors;

  /// Optional normalized stop positions for [colors].
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
}

class _GrainOp {
  /// Distance between adjacent grain samples in logical pixels.
  final double spacing;

  /// Vertical extent of the grain field as a fraction of canvas height.
  final double limitYFactor;

  /// Minimum hashed noise value required before a grain dot is drawn.
  final double noiseThreshold;

  /// Multiplier applied to the post-threshold noise value for alpha.
  final double opacityScale;

  /// Smallest possible grain radius.
  final double minRadius;

  /// Extra radius added on top of [minRadius] as noise increases.
  final double maxRadiusDelta;

  /// Color used for lower-noise grain dots.
  final Color fromColor;

  /// Color used for higher-noise grain dots.
  final Color toColor;

  /// Controls how aggressively noise shifts the dot color toward [toColor].
  final double colorLerpScale;

  /// Center of the radial fade in Flutter's alignment space.
  final Alignment fadeCenter;

  /// Radius of the radial fade in normalized canvas space.
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
  /// Distance between halftone sample points in logical pixels.
  final double spacing;

  /// Baseline top edge of the halftone field as a fraction of canvas height.
  final double startYFactor;

  /// Dot radius right at the local frontier.
  final double baseRadius;

  /// Additional radius gained as a dot moves away from the frontier.
  final double radiusGrowth;

  /// Minimum alpha applied to halftone dots.
  final double opacityBase;

  /// Extra alpha added as dots move toward the top of the field.
  final double opacityGrowth;

  /// Color used near the upper part of the halftone field.
  final Color topColor;

  /// Color used near the lower part of the halftone field.
  final Color bottomColor;

  /// Controls how strongly the vertical gradient interpolates toward [topColor].
  final double colorLerpScale;

  /// Depth of the curved frontier as a fraction of canvas height.
  final double convexCurveDepthFactor;

  /// Extra curve depth applied on wider layouts.
  final double landscapeCurveBoost;

  /// Shapes how quickly the frontier lifts toward the center versus the edges.
  final double curveExponent;

  /// Reduces [curveExponent] on wide layouts to soften the curve.
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
