import 'package:flutter/material.dart';

class AuthPalette {
  const AuthPalette._();

  static const Color panel = Color(0xFFE3E3E7);
  static const Color panelBorder = Color(0x29FFFFFF);
  static const Color panelShadow = Color(0x38000000);
  static const Color fabIcon = panel;
  static const Color fabGlass = Color(0x40E3E3E7);
  static const Color fabShadow = Color(0x30000000);
  static const Color buttonForeground = Colors.white;
  static const Color secondaryButtonForeground = Colors.white;
  static const Color primaryButtonBase = Color(0xFF451AAC);
  static const Color secondaryButtonBase = Color(0xFF5935AD);
  static const Color buttonBorder = Color(0x33FFFFFF);
  static const Color buttonShadow = Color(0x18000000);

  static const List<Color> baseGradientColors = [
    Color(0xFF7716A4),
    Color(0xFF5D148F),
    Color(0xFF33104F),
    Color(0xFF0B0716),
    Color(0xFF000000),
  ];

  static const List<double> baseGradientStops = [0.0, 0.3, 0.58, 0.82, 1.0];

  static const List<Color> bloomColors = [
    Color(0xFFFC2FA7),
    Color(0xEEFA42B2),
    Color(0xA0CC33DE),
    Color(0x003E0D63),
  ];

  static const List<double> bloomStops = [0.0, 0.24, 0.52, 1.0];

  static const List<Color> transitionColors = [
    Color(0x00FFFFFF),
    Color(0x44320D57),
    Color(0xAA09040F),
    Color(0xFF010103),
  ];

  static const List<double> transitionStops = [0.22, 0.56, 0.82, 1.0];

  static const List<Color> floorFadeColors = [
    Color(0x00000000),
    Color(0xA6000000),
    Color(0xFF000000),
  ];

  static const List<double> floorFadeStops = [0.72, 0.9, 1.0];

  static const Color grainFrom = Color(0xFF16040B);
  static const Color grainTo = Color(0xFF9A41DB);
  static const Color halftoneTop = Color.fromARGB(255, 10, 2, 25);
  static const Color halftoneBottom = halftoneTop;
}
