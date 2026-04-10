import 'package:flutter/material.dart';

class AuthPalette {
  const AuthPalette._();

  static const Color logoText = Color(0xFFFFEAF7);
  static const Color panel = Color(0xFFE3E3E7);
  static const Color panelBorder = Color(0x29FFFFFF);
  static const Color panelShadow = Color(0x38000000);
  static const Color fabIcon = panel;
  static const Color buttonForeground = Colors.white;

  static const List<Color> baseGradientColors = [
    Color(0xFF7716A4),
    Color(0xFF5D148F),
    Color(0xFF33104F),
    Color(0xFF0B0716),
    Color(0xFF020105),
  ];

  static const List<double> baseGradientStops = [0.0, 0.3, 0.58, 0.82, 1.0];

  static const List<Color> bloomColors = [
    Color(0xFFFF4CB8),
    Color(0xFFF336B0),
    Color(0xFFC42ADE),
    Color(0x00571A84),
  ];

  static const List<double> bloomStops = [0.0, 0.28, 0.62, 1.0];

  static const List<Color> transitionColors = [
    Color(0x00FFFFFF),
    Color(0x44320D57),
    Color(0xAA09040F),
    Color(0xFF010103),
  ];

  static const List<double> transitionStops = [0.22, 0.56, 0.82, 1.0];

  static const Color grainFrom = Color(0xFF22051E);
  static const Color grainTo = Color(0xFF7B28B0);
  static const Color halftoneFrom = Color(0xFF6D20BE);
  static const Color halftoneTo = Color(0xFF010103);
}
