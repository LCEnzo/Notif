import 'package:flutter/material.dart';

class FeedbackColors {
  const FeedbackColors._();

  static const Color error = Color(0xFFB04040);
  static const Color success = Color(0xFF5A8A5E);
  static const Color warning = Color(0xFFB09040);
}

class NotifDesignTokens {
  const NotifDesignTokens._();

  static const Color structBg = Color(0xFF0D0B0F);
  static const Color structSurface = Color(0xFF16131A);
  static const Color structRaised = Color(0xFF1E1A24);
  static const Color structText = Color(0xFFE8E4E0);
  static const Color structText2 = Color(0xFFB0AAA3);
  static const Color structText3 = Color(0xFF706B65);
  static const Color structBorder = Color(0xFF2A2630);
  static const Color structDivider = Color(0xFF1F1B25);

  static const Color accentPrimary = Color(0xFF6B3FA0);
  static const Color accentMuted = Color(0xFF4A3070);
  static const Color accentDim = Color(0xFF2A1C45);
  static const Color accentText = Color(0xFFB89FD4);
  static const Color accentOnAccent = structText;

  static const String displayFont = 'InstrumentSerif';
  static const String bodyFont = 'Skyling';
  static const String altBodyFont = 'ZalandoSans';
  static const String monoFont = 'SuisseMono';

  static const double radiusNone = 0;
  static const double radiusSm = 4;
  static const double radiusAuth = 6;

  static const double borderWidth = 1;
  static const double borderFocusWidth = 2;

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceBase = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double space2xl = 48;

  static const Duration microMotion = Duration(milliseconds: 110);
  static const Duration shortMotion = Duration(milliseconds: 180);
  static const Duration pageMotion = Duration(milliseconds: 220);

  static BorderSide get ruleSide =>
      const BorderSide(color: structBorder, width: borderWidth);

  static BorderSide get dividerSide =>
      const BorderSide(color: structDivider, width: borderWidth);

  static BorderRadius get flatRadius => BorderRadius.circular(radiusNone);

  static BorderRadius get softRadius => BorderRadius.circular(radiusSm);

  static const TextStyle buttonTextStyle = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    letterSpacing: 1.2,
  );

  static ButtonStyle framedButtonStyle({required bool isPrimary}) {
    return ButtonStyle(
      animationDuration: microMotion,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 16 / 12,
          letterSpacing: 1.2,
        ),
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (isPrimary) {
          return accentOnAccent;
        }
        if (states.contains(WidgetState.pressed)) {
          return accentOnAccent;
        }
        return accentText;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (isPrimary) {
          if (states.contains(WidgetState.pressed)) {
            return Color.lerp(accentPrimary, Colors.black, 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return Color.lerp(accentPrimary, structText, 0.08);
          }
          return accentPrimary;
        }

        if (states.contains(WidgetState.pressed)) {
          return accentMuted;
        }
        if (states.contains(WidgetState.hovered)) {
          return accentDim;
        }
        return Colors.transparent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (isPrimary) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: accentDim, width: borderFocusWidth);
          }
          return BorderSide.none;
        }

        if (states.contains(WidgetState.focused)) {
          return const BorderSide(color: accentDim, width: borderFocusWidth);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return const BorderSide(color: accentMuted, width: borderWidth);
        }
        return const BorderSide(color: structBorder, width: borderWidth);
      }),
      overlayColor: WidgetStatePropertyAll(accentText.withValues(alpha: 0.06)),
    );
  }
}
