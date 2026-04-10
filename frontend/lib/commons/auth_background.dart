import 'dart:math';

import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';

class PageBackground extends StatelessWidget {
  final Widget child;

  const PageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: const _PosterBackgroundPainter(),
        child: child,
      ),
    );
  }
}

class _PosterBackgroundPainter extends CustomPainter {
  const _PosterBackgroundPainter();

  static const List<_BackgroundOp> _operations = [
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.baseGradientColors,
      stops: AuthPalette.baseGradientStops,
    ),
    _CircularGradientOp(
      centerYFactor: 0,
      diameterFactor: 0.78,
      colors: AuthPalette.bloomColors,
      stops: AuthPalette.bloomStops,
    ),
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.transitionColors,
      stops: AuthPalette.transitionStops,
    ),
    _GrainOp(
      spacing: 2.6,
      limitYFactor: 1,
      noiseThreshold: 0.09,
      opacityScale: 0.34,
      minRadius: 0.26,
      maxRadiusDelta: 0.38,
      fromColor: AuthPalette.grainFrom,
      toColor: AuthPalette.grainTo,
      colorLerpScale: 0.68,
      fadeCenter: Alignment(0, -1),
      fadeRadius: 2.85,
    ),
    _HalftoneOp(
      spacing: 13,
      startYFactor: 0.4,
      baseRadius: 1.5,
      radiusGrowth: 6.6,
      opacityBase: 0.16,
      opacityGrowth: 0.26,
      topColor: AuthPalette.halftoneTop,
      bottomColor: AuthPalette.halftoneBottom,
      colorLerpScale: 0.66,
      convexCurveDepthFactor: 0.16,
      landscapeCurveBoost: 1.15,
      curveExponent: 1.7,
      landscapeExponentPull: 0.35,
    ),
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.floorFadeColors,
      stops: AuthPalette.floorFadeStops,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final operation in _operations) {
      operation.paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
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
}

class _GrainOp extends _BackgroundOp {
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final limitY = size.height * limitYFactor;
    final cx = (fadeCenter.x + 1) / 2 * size.width;
    final cy = (fadeCenter.y + 1) / 2 * size.height;
    final halfW = size.width * 0.5;
    final halfH = size.height * 0.5;
    var rowIndex = 0;

    for (double y = 0; y < limitY; y += spacing) {
      final offsetX = rowIndex.isEven ? 0.0 : spacing / 2;

      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final dotX = x + offsetX;
        final nx = (dotX - cx) / halfW;
        final ny = (y - cy) / halfH;
        final dist = sqrt(nx * nx + ny * ny);
        final radialFade = (1.0 - dist / fadeRadius).clamp(0.0, 1.0);

        if (radialFade <= 0) continue;

        final noise = _hashNoise(
          ((x + spacing) / spacing).floor(),
          (y / spacing).floor(),
        );
        if (noise < noiseThreshold) continue;

        final alpha = (noise - noiseThreshold) * opacityScale * radialFade;
        paint.color = Color.lerp(
          fromColor,
          toColor,
          noise * colorLerpScale,
        )!.withValues(alpha: alpha);

        canvas.drawCircle(
          Offset(dotX, y),
          minRadius + noise * maxRadiusDelta,
          paint,
        );
      }

      rowIndex++;
    }
  }
}

class _HalftoneOp extends _BackgroundOp {
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final startY = size.height * startYFactor;
    final aspectRatio = size.width / size.height;
    final landscapeFactor = (aspectRatio - 1).clamp(0.0, 1.8);
    final curveDepth =
        size.height *
        convexCurveDepthFactor *
        (1 + landscapeFactor * landscapeCurveBoost);
    final exponent = (curveExponent - landscapeFactor * landscapeExponentPull)
        .clamp(0.7, 4.0);
    var rowIndex = 0;

    for (double y = startY; y < size.height + spacing; y += spacing) {
      final normalized = ((y - startY) / (size.height - startY)).clamp(0.0, 1.0);
      final contrastFactor = 1 - normalized;
      final xOffset = rowIndex.isEven ? 0.0 : spacing / 2;
      final radius = baseRadius + normalized * radiusGrowth;

      paint.color = Color.lerp(
            bottomColor,
            topColor,
            contrastFactor * colorLerpScale,
          )!
          .withOpacity(opacityBase + contrastFactor * opacityGrowth);

      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final currentX = x + xOffset;
        final centerDistance =
            ((currentX - (size.width / 2)).abs() / (size.width / 2))
                .clamp(0.0, 1.0);
        final edgeLift = 1 - pow(centerDistance, exponent).toDouble();
        final localStartY = startY + curveDepth * edgeLift;
        if (y < localStartY) {
          continue;
        }

        canvas.drawCircle(Offset(currentX, y), radius, paint);
      }

      rowIndex++;
    }
  }
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

double _hashNoise(int x, int y) {
  int value = x * 374761393 + y * 668265263;
  value = (value ^ (value >> 13)) * 1274126177;
  value ^= value >> 16;
  return (value & 0x7fffffff) / 0x7fffffff;
}
