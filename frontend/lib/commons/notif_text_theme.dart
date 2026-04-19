import 'package:flutter/material.dart';

/// Three typography "sets" defined in `style-guide-todo.md` §6.3. The user
/// picks one in Settings; the theme rebuilds on change.
///
/// - [current]    — existing 6-role scale (Instrument Serif / Skyling / Suisse
///                  Mono / Zalando Sans). Ships today.
/// - [experiment] — 8-role scale using Newsreader, JetBrains Mono, and
///                  Inter Tight.
/// - [hybrid]     — 8-role scale with the *current* registered fonts.
enum NotifFontSet { current, experiment, hybrid }

extension NotifFontSetMeta on NotifFontSet {
  String get displayName {
    switch (this) {
      case NotifFontSet.current:
        return 'Current';
      case NotifFontSet.experiment:
        return 'Experiment';
      case NotifFontSet.hybrid:
        return 'Hybrid';
    }
  }

  String get description {
    switch (this) {
      case NotifFontSet.current:
        return 'Instrument Serif · Skyling · Suisse Mono. '
            'Six-role scale, ships today.';
      case NotifFontSet.experiment:
        return 'Eight-role scale with Newsreader, JetBrains Mono, and '
            'Inter Tight.';
      case NotifFontSet.hybrid:
        return 'Eight-role scale on the current fonts. '
            'Long-read body borrows Instrument Serif italic.';
    }
  }
}

/// Canonical family identifiers. Matches `pubspec.yaml` entries.
class NotifFontFamilies {
  const NotifFontFamilies._();
  static const String instrumentSerif = 'InstrumentSerif';
  static const String interTight = 'InterTight';
  static const String jetBrainsMono = 'JetBrainsMono';
  static const String newsreader = 'Newsreader';
  static const String skyling = 'Skyling';
  static const String zalandoSans = 'ZalandoSans';
  static const String suisseMono = 'SuisseMono';
}

/// ThemeExtension carrying the eight canonical text roles plus Flutter's
/// built-in [TextTheme] so Material widgets keep working.
///
/// Every role is required — no silent fallbacks. Callers read roles through
/// [NotifTextTheme.of] and the compiler enforces that every role is resolved.
@immutable
class NotifTextTheme extends ThemeExtension<NotifTextTheme> {
  const NotifTextTheme({
    required this.fontSet,
    required this.display,
    required this.title,
    required this.heading,
    required this.eyebrow,
    required this.body,
    required this.bodyLong,
    required this.micro,
    required this.code,
  });

  final NotifFontSet fontSet;

  final TextStyle display;
  final TextStyle title;
  final TextStyle heading;
  final TextStyle eyebrow;
  final TextStyle body;
  final TextStyle bodyLong;
  final TextStyle micro;
  final TextStyle code;

  static NotifTextTheme of(BuildContext context) {
    final theme = Theme.of(context).extension<NotifTextTheme>();
    if (theme == null) {
      throw StateError(
        'NotifTextTheme extension missing from Theme. '
        'Wrap MaterialApp with a theme built via buildNotifTheme().',
      );
    }
    return theme;
  }

  /// Build a Flutter [TextTheme] from the eight roles. Material widgets that
  /// don't know about our named roles (`bodyMedium` on `ListTile`, etc.)
  /// still get reasonable defaults.
  TextTheme toMaterialTextTheme() {
    return TextTheme(
      displayLarge: display,
      displayMedium: title,
      displaySmall: heading,
      headlineLarge: title,
      headlineMedium: heading,
      headlineSmall: heading,
      titleLarge: heading,
      titleMedium: body,
      titleSmall: body,
      bodyLarge: bodyLong,
      bodyMedium: body,
      bodySmall: code,
      labelLarge: eyebrow,
      labelMedium: eyebrow,
      labelSmall: micro,
    );
  }

  factory NotifTextTheme.forSet(NotifFontSet set) {
    switch (set) {
      case NotifFontSet.current:
        return _buildCurrent();
      case NotifFontSet.experiment:
        return _buildExperiment();
      case NotifFontSet.hybrid:
        return _buildHybrid();
    }
  }

  @override
  NotifTextTheme copyWith({
    NotifFontSet? fontSet,
    TextStyle? display,
    TextStyle? title,
    TextStyle? heading,
    TextStyle? eyebrow,
    TextStyle? body,
    TextStyle? bodyLong,
    TextStyle? micro,
    TextStyle? code,
  }) {
    return NotifTextTheme(
      fontSet: fontSet ?? this.fontSet,
      display: display ?? this.display,
      title: title ?? this.title,
      heading: heading ?? this.heading,
      eyebrow: eyebrow ?? this.eyebrow,
      body: body ?? this.body,
      bodyLong: bodyLong ?? this.bodyLong,
      micro: micro ?? this.micro,
      code: code ?? this.code,
    );
  }

  @override
  NotifTextTheme lerp(ThemeExtension<NotifTextTheme>? other, double t) {
    if (other is! NotifTextTheme) return this;
    if (fontSet != other.fontSet) return t < 0.5 ? this : other;
    return NotifTextTheme(
      fontSet: fontSet,
      display: TextStyle.lerp(display, other.display, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      heading: TextStyle.lerp(heading, other.heading, t)!,
      eyebrow: TextStyle.lerp(eyebrow, other.eyebrow, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyLong: TextStyle.lerp(bodyLong, other.bodyLong, t)!,
      micro: TextStyle.lerp(micro, other.micro, t)!,
      code: TextStyle.lerp(code, other.code, t)!,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared role shapes (used by all three sets).
// Uppercase roles (eyebrow, micro) apply `.toUpperCase()` at the widget
// level — TextStyle has no textTransform. See Eyebrow / Tag / KV components.
// ─────────────────────────────────────────────────────────────

TextStyle _mono({
  required String family,
  required double size,
  required double lineHeight,
  double letterSpacing = 0,
  FontWeight weight = FontWeight.w400,
}) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    letterSpacing: letterSpacing,
    fontWeight: weight,
  );
}

TextStyle _serif({
  required String family,
  required double size,
  required double lineHeight,
  double letterSpacing = 0,
  FontWeight weight = FontWeight.w400,
  FontStyle style = FontStyle.normal,
}) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    letterSpacing: letterSpacing,
    fontWeight: weight,
    fontStyle: style,
  );
}

TextStyle _sans({
  required String family,
  required double size,
  required double lineHeight,
  double letterSpacing = 0,
  FontWeight weight = FontWeight.w400,
}) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    letterSpacing: letterSpacing,
    fontWeight: weight,
  );
}

// ─────────────────────────────────────────────────────────────
// Current set — 6-role scale, preserved verbatim from the existing app.
// Roles that don't exist in the 6-role scale (eyebrow, bodyLong, micro,
// code) fall back to the closest existing style.
// ─────────────────────────────────────────────────────────────
NotifTextTheme _buildCurrent() {
  // Existing style values from about.dart / settings.dart pre-refactor. §6.2
  // picks 22 as the canonical title size (resolving the 20/26 drift).
  const serif = NotifFontFamilies.instrumentSerif;
  const sans = NotifFontFamilies.skyling;
  const mono = NotifFontFamilies.suisseMono;

  final display = _serif(family: serif, size: 34, lineHeight: 42, letterSpacing: -0.5);
  final title = _serif(family: serif, size: 22, lineHeight: 28);
  final heading = _serif(family: serif, size: 22, lineHeight: 28);

  // Current set's `label` (12sp, +1.2 tracking, w500). Maps to eyebrow/micro.
  final label = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
  );

  final body = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 22 / 15,
    letterSpacing: 0.1,
  );

  // Current set has no long-read serif. bodyLong falls back to body — spec
  // §6.3 explicitly allows this, and §6.4 forbids faking it with italic.
  final bodyLong = body;

  final code = TextStyle(
    fontFamily: mono,
    fontSize: 14,
    height: 20 / 14,
  );

  return NotifTextTheme(
    fontSet: NotifFontSet.current,
    display: display,
    title: title,
    heading: heading,
    eyebrow: label,
    body: body,
    bodyLong: bodyLong,
    micro: label.copyWith(fontSize: 10.5, letterSpacing: 1.5),
    code: code,
  );
}

// ─────────────────────────────────────────────────────────────
// Experiment set — 8-role scale using the full experiment families.
// Inter Tight is the registered utility sans even though the current eight
// canonical roles do not resolve to it by default.
// ─────────────────────────────────────────────────────────────
NotifTextTheme _buildExperiment() {
  const serif = NotifFontFamilies.instrumentSerif;
  const serifLong = NotifFontFamilies.newsreader;
  const sans = NotifFontFamilies.interTight;
  const mono = NotifFontFamilies.jetBrainsMono;

  // Utility sans (Inter Tight) carries body copy. bodyLong stays on the
  // long-read serif; eyebrow/micro/code stay on mono. Matches §6.3 intent:
  // "Newsreader, JetBrains Mono, and Inter Tight."
  return NotifTextTheme(
    fontSet: NotifFontSet.experiment,
    display: _serif(family: serif, size: 64, lineHeight: 61, letterSpacing: -1.28),
    title: _serif(family: serif, size: 40, lineHeight: 41, letterSpacing: -0.60),
    heading: _serif(family: serif, size: 22, lineHeight: 25, letterSpacing: -0.22),
    eyebrow: _mono(family: mono, size: 11, lineHeight: 11, letterSpacing: 2.2, weight: FontWeight.w500),
    body: _sans(family: sans, size: 14, lineHeight: 22),
    bodyLong: _serif(family: serifLong, size: 15, lineHeight: 23),
    micro: _mono(family: mono, size: 10.5, lineHeight: 14, letterSpacing: 1.26, weight: FontWeight.w500),
    code: _mono(family: mono, size: 12, lineHeight: 18),
  );
}

// ─────────────────────────────────────────────────────────────
// Hybrid set — 8-role scale on the *current* registered fonts.
// - serif / serifLong  → Instrument Serif (italic for bodyLong)
// - utility sans       → Skyling
// - all mono           → Suisse Mono
// ─────────────────────────────────────────────────────────────
NotifTextTheme _buildHybrid() {
  const serif = NotifFontFamilies.instrumentSerif;
  const mono = NotifFontFamilies.suisseMono;

  return NotifTextTheme(
    fontSet: NotifFontSet.hybrid,
    display: _serif(family: serif, size: 64, lineHeight: 61, letterSpacing: -1.28),
    title: _serif(family: serif, size: 40, lineHeight: 41, letterSpacing: -0.60),
    heading: _serif(family: serif, size: 22, lineHeight: 25, letterSpacing: -0.22),
    eyebrow: _mono(family: mono, size: 11, lineHeight: 11, letterSpacing: 2.2, weight: FontWeight.w500),
    body: _mono(family: mono, size: 13, lineHeight: 20),
    bodyLong: _serif(family: serif, size: 15, lineHeight: 23, style: FontStyle.italic),
    micro: _mono(family: mono, size: 10.5, lineHeight: 14, letterSpacing: 1.26, weight: FontWeight.w500),
    code: _mono(family: mono, size: 12, lineHeight: 18),
  );
}
