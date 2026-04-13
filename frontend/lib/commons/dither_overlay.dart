import 'package:flutter/material.dart';
import 'package:notif/commons/notif_design_tokens.dart';

class DitherOverlay extends StatelessWidget {
  const DitherOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _DitherOverlayPainter()),
        ),
      ),
    );
  }
}

class _DitherOverlayPainter extends CustomPainter {
  const _DitherOverlayPainter();

  static const _step = 5.0;
  static const _neutralAlpha = 0.018;
  static const _accentAlpha = 0.014;
  static const _accentCutoff = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    final neutralPaint = Paint()
      ..color = NotifDesignTokens.structText.withValues(alpha: _neutralAlpha);
    final accentPaint = Paint()
      ..color = NotifDesignTokens.accentText.withValues(alpha: _accentAlpha);

    for (double y = 0; y < size.height; y += _step) {
      for (double x = 0; x < size.width; x += _step) {
        final cellX = (x / _step).floor();
        final cellY = (y / _step).floor();
        final hash = ((cellX * 73856093) ^ (cellY * 19349663)) & 7;

        if (hash == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), neutralPaint);
        } else if (hash == 1 && y < size.height * _accentCutoff) {
          canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, 1, 1), accentPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DitherOverlayPainter oldDelegate) => false;
}
