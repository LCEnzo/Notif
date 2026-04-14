import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/notif_design_tokens.dart';

class DitherOverlay extends StatelessWidget {
  const DitherOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // GLSL shaders are unsupported on web — skip the overlay entirely.
    if (kIsWeb) return const SizedBox.shrink();

    return const Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: _DitherShaderLayer(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shader program — compiled once, cached forever.
// ---------------------------------------------------------------------------

final Future<ui.FragmentProgram> _ditherProgram =
    ui.FragmentProgram.fromAsset('shaders/dither_overlay.frag');

// ---------------------------------------------------------------------------
// Widget — waits for the shader to load, then paints with it.
// ---------------------------------------------------------------------------

class _DitherShaderLayer extends StatelessWidget {
  const _DitherShaderLayer();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _ditherProgram,
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
          painter: _DitherShaderPainter(program: program, dpr: dpr),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Painter — sets uniforms and draws a full-viewport rect.
// ---------------------------------------------------------------------------

class _DitherShaderPainter extends CustomPainter {
  /// Grid cell size in logical pixels (matches the original CustomPainter).
  static const double _stepLogical = 5.0;
  static const double _neutralAlpha = 0.018;
  static const double _accentAlpha = 0.014;
  static const double _accentCutoff = 0.42;

  final ui.FragmentProgram program;
  final double dpr;

  const _DitherShaderPainter({required this.program, required this.dpr});

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    var i = 0;

    // uSize — physical pixels so it matches FlutterFragCoord().xy
    shader.setFloat(i++, size.width * dpr);
    shader.setFloat(i++, size.height * dpr);

    // uNeutralColor — structText with neutral alpha
    i = _setColorRGBA(shader, i, NotifDesignTokens.structText, _neutralAlpha);

    // uAccentColor — accentText with accent alpha
    i = _setColorRGBA(shader, i, NotifDesignTokens.accentText, _accentAlpha);

    // uAccentCutoff
    shader.setFloat(i++, _accentCutoff);

    // uStep — scaled to physical pixels so grid density is
    // resolution-independent (same number of dots per logical inch).
    shader.setFloat(i++, _stepLogical * dpr);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _DitherShaderPainter oldDelegate) {
    return oldDelegate.program != program || oldDelegate.dpr != dpr;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pass [color]'s RGB plus an explicit [alpha] as 4 floats (R, G, B, A).
int _setColorRGBA(ui.FragmentShader shader, int index, Color color, double alpha) {
  final argb = color.toARGB32();
  shader.setFloat(index++, ((argb >> 16) & 0xFF) / 255.0); // R
  shader.setFloat(index++, ((argb >> 8) & 0xFF) / 255.0);  // G
  shader.setFloat(index++, (argb & 0xFF) / 255.0);          // B
  shader.setFloat(index++, alpha);                           // A (override)
  return index;
}
