import 'package:flutter/material.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

/// Assemble the full Flutter [ThemeData] from the user's current colorway and
/// font-set picks. Single source of truth for the app's visual
/// surface: the picker writes to [AppSettingsController], this file renders it.
ThemeData buildNotifTheme({
  required NotifColorway colorway,
  required NotifFontSet fontSet,
}) {
  final tokens = NotifTokens.build(colorway);
  final textTheme = NotifTextTheme.forSet(fontSet);
  final materialText = textTheme.toMaterialTextTheme();

  final colorScheme = tokens.brightness == Brightness.dark
      ? ColorScheme.dark(
          surface: tokens.bg1,
          primary: tokens.btnBg,
          onPrimary: tokens.btnInk,
          secondary: tokens.accent,
          onSecondary: tokens.bg1,
          error: NotifFeedback.error,
          onError: tokens.ink,
          onSurface: tokens.ink,
        )
      : ColorScheme.light(
          surface: tokens.bg1,
          primary: tokens.btnBg,
          onPrimary: tokens.btnInk,
          secondary: tokens.accent,
          onSecondary: tokens.bg1,
          error: NotifFeedback.error,
          onError: tokens.ink,
          onSurface: tokens.ink,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.bg1,
    canvasColor: tokens.bg1,
    textTheme: materialText,
    primaryTextTheme: materialText,
    extensions: <ThemeExtension<dynamic>>[tokens, textTheme],
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bg1,
      foregroundColor: tokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.heading.copyWith(color: tokens.ink),
    ),
    dividerTheme: DividerThemeData(color: tokens.rule, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: tokens.inkDim, size: 18),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accent.withValues(alpha: 0.32),
      selectionHandleColor: tokens.accent,
    ),
  );
}
