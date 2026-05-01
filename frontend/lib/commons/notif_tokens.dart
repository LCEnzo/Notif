import 'package:flutter/material.dart';

/// Which named colorway is active. The set here matches `style-guide-todo.md`
/// §4. Adding a new colorway means adding a value here and a corresponding
/// entry in [_NotifColorwayRegistry] — everything else is exhaustive, so the
/// compiler flags the gap.
enum NotifColorway { dusk1, dusk2, midnight, sage, daybreak }

extension NotifColorwayMeta on NotifColorway {
  String get code {
    switch (this) {
      case NotifColorway.dusk1:
        return '01';
      case NotifColorway.dusk2:
        return '02';
      case NotifColorway.midnight:
        return '03';
      case NotifColorway.sage:
        return '04';
      case NotifColorway.daybreak:
        return '05';
    }
  }

  String get displayName {
    switch (this) {
      case NotifColorway.dusk1:
        return 'Dusk 1';
      case NotifColorway.dusk2:
        return 'Dusk 2';
      case NotifColorway.midnight:
        return 'Midnight';
      case NotifColorway.sage:
        return 'Sage';
      case NotifColorway.daybreak:
        return 'Daybreak';
    }
  }

  String get description {
    switch (this) {
      case NotifColorway.dusk1:
        return 'Default. Warm violet. Current app identity.';
      case NotifColorway.dusk2:
        return 'Hotter magenta-pink. Harder edge.';
      case NotifColorway.midnight:
        return 'Radio static in the ocean trench.';
      case NotifColorway.sage:
        return 'Aged paper and cactus. Urbit field journal.';
      case NotifColorway.daybreak:
        return 'Coastal daylight. Counterpart to Midnight.';
    }
  }

  Brightness get brightness {
    switch (this) {
      case NotifColorway.dusk1:
      case NotifColorway.dusk2:
      case NotifColorway.midnight:
        return Brightness.dark;
      case NotifColorway.sage:
      case NotifColorway.daybreak:
        return Brightness.light;
    }
  }
}

/// Shared feedback colors — same across every colorway. Revisit light-scheme
/// contrast per §14 once we have Sage / Daybreak in actual use.
class NotifFeedback {
  const NotifFeedback._();
  static const Color error = Color(0xFFB04040);
  static const Color success = Color(0xFF5A8A5E);
  static const Color warning = Color(0xFFB09040);
}

@immutable
class AuthBackdropColors {
  const AuthBackdropColors({
    required this.baseGradientColors,
    required this.bloomColors,
    required this.transitionColors,
    required this.floorFadeColors,
    required this.grainFrom,
    required this.grainTo,
    required this.halftoneTop,
    required this.halftoneBottom,
  });

  final List<Color> baseGradientColors;
  final List<Color> bloomColors;
  final List<Color> transitionColors;
  final List<Color> floorFadeColors;
  final Color grainFrom;
  final Color grainTo;
  final Color halftoneTop;
  final Color halftoneBottom;

  AuthBackdropColors lerp(AuthBackdropColors other, double t) {
    return AuthBackdropColors(
      baseGradientColors: _lerpColorList(
        baseGradientColors,
        other.baseGradientColors,
        t,
      ),
      bloomColors: _lerpColorList(bloomColors, other.bloomColors, t),
      transitionColors: _lerpColorList(
        transitionColors,
        other.transitionColors,
        t,
      ),
      floorFadeColors: _lerpColorList(
        floorFadeColors,
        other.floorFadeColors,
        t,
      ),
      grainFrom: Color.lerp(grainFrom, other.grainFrom, t)!,
      grainTo: Color.lerp(grainTo, other.grainTo, t)!,
      halftoneTop: Color.lerp(halftoneTop, other.halftoneTop, t)!,
      halftoneBottom: Color.lerp(halftoneBottom, other.halftoneBottom, t)!,
    );
  }

  static List<Color> _lerpColorList(
    List<Color> a,
    List<Color> b,
    double t,
  ) {
    assert(a.length == b.length, 'Auth backdrop color lists must align.');
    return [
      for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
    ];
  }
}

/// Full token set per colorway. Consumed through [NotifTokens] on the Theme
/// extension. Every field is required — no missing tokens, no fallbacks —
/// because the spec (§3) treats a gap as a colorway bug.
@immutable
class NotifTokens extends ThemeExtension<NotifTokens> {
  const NotifTokens({
    required this.colorway,
    required this.bg0,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.halo1,
    required this.halo2,
    required this.halo3,
    required this.ink,
    required this.inkDim,
    required this.inkMute,
    required this.inkFaint,
    required this.accent,
    required this.accent2,
    required this.rule,
    required this.ruleStrong,
    required this.btnBg,
    required this.btnInk,
    required this.btnBgAlt,
    required this.btnInkAlt,
    required this.halftone,
    required this.halftoneBlend,
    required this.grainOpacity,
    required this.authBackdrop,
  });

  final NotifColorway colorway;

  // Structural
  final Color bg0;
  final Color bg1;
  final Color bg2;
  final Color bg3;

  // Halo (atmospheric)
  final Color halo1;
  final Color halo2;
  final Color halo3;

  // Text
  final Color ink;
  final Color inkDim;
  final Color inkMute;
  final Color inkFaint;

  // Chromatic
  final Color accent;
  final Color accent2;

  // Rules
  final Color rule;
  final Color ruleStrong;

  // Interactive
  final Color btnBg;
  final Color btnInk;
  final Color btnBgAlt;
  final Color btnInkAlt;

  // Texture
  final Color halftone;
  final BlendMode halftoneBlend;
  final double grainOpacity;
  final AuthBackdropColors authBackdrop;

  Brightness get brightness => colorway.brightness;

  /// Build the tokens for a given colorway. Each colorway owns its own
  /// brightness, so there is no separate scheme selection to resolve.
  factory NotifTokens.build(NotifColorway colorway) {
    final build = _NotifColorwayRegistry.tokens[colorway];
    if (build == null) {
      throw StateError(
        'Missing registry entry for ${colorway.name}. All enum values must '
        'be registered in _NotifColorwayRegistry.tokens.',
      );
    }
    return build();
  }

  @override
  NotifTokens copyWith({
    NotifColorway? colorway,
    Color? bg0,
    Color? bg1,
    Color? bg2,
    Color? bg3,
    Color? halo1,
    Color? halo2,
    Color? halo3,
    Color? ink,
    Color? inkDim,
    Color? inkMute,
    Color? inkFaint,
    Color? accent,
    Color? accent2,
    Color? rule,
    Color? ruleStrong,
    Color? btnBg,
    Color? btnInk,
    Color? btnBgAlt,
    Color? btnInkAlt,
    Color? halftone,
    BlendMode? halftoneBlend,
    double? grainOpacity,
    AuthBackdropColors? authBackdrop,
  }) {
    return NotifTokens(
      colorway: colorway ?? this.colorway,
      bg0: bg0 ?? this.bg0,
      bg1: bg1 ?? this.bg1,
      bg2: bg2 ?? this.bg2,
      bg3: bg3 ?? this.bg3,
      halo1: halo1 ?? this.halo1,
      halo2: halo2 ?? this.halo2,
      halo3: halo3 ?? this.halo3,
      ink: ink ?? this.ink,
      inkDim: inkDim ?? this.inkDim,
      inkMute: inkMute ?? this.inkMute,
      inkFaint: inkFaint ?? this.inkFaint,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      rule: rule ?? this.rule,
      ruleStrong: ruleStrong ?? this.ruleStrong,
      btnBg: btnBg ?? this.btnBg,
      btnInk: btnInk ?? this.btnInk,
      btnBgAlt: btnBgAlt ?? this.btnBgAlt,
      btnInkAlt: btnInkAlt ?? this.btnInkAlt,
      halftone: halftone ?? this.halftone,
      halftoneBlend: halftoneBlend ?? this.halftoneBlend,
      grainOpacity: grainOpacity ?? this.grainOpacity,
      authBackdrop: authBackdrop ?? this.authBackdrop,
    );
  }

  /// Cross-colorway lerping doesn't have a meaningful mid-point — two
  /// colorways are distinct identities, not points on a continuum. We
  /// snap at the midpoint so animated theme swaps look like a decisive
  /// cut rather than a smeared blend.
  @override
  NotifTokens lerp(ThemeExtension<NotifTokens>? other, double t) {
    if (other is! NotifTokens) return this;
    if (colorway == other.colorway) {
      return NotifTokens(
        colorway: colorway,
        bg0: Color.lerp(bg0, other.bg0, t)!,
        bg1: Color.lerp(bg1, other.bg1, t)!,
        bg2: Color.lerp(bg2, other.bg2, t)!,
        bg3: Color.lerp(bg3, other.bg3, t)!,
        halo1: Color.lerp(halo1, other.halo1, t)!,
        halo2: Color.lerp(halo2, other.halo2, t)!,
        halo3: Color.lerp(halo3, other.halo3, t)!,
        ink: Color.lerp(ink, other.ink, t)!,
        inkDim: Color.lerp(inkDim, other.inkDim, t)!,
        inkMute: Color.lerp(inkMute, other.inkMute, t)!,
        inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
        accent: Color.lerp(accent, other.accent, t)!,
        accent2: Color.lerp(accent2, other.accent2, t)!,
        rule: Color.lerp(rule, other.rule, t)!,
        ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!,
        btnBg: Color.lerp(btnBg, other.btnBg, t)!,
        btnInk: Color.lerp(btnInk, other.btnInk, t)!,
        btnBgAlt: Color.lerp(btnBgAlt, other.btnBgAlt, t)!,
        btnInkAlt: Color.lerp(btnInkAlt, other.btnInkAlt, t)!,
        halftone: Color.lerp(halftone, other.halftone, t)!,
        halftoneBlend: t < 0.5 ? halftoneBlend : other.halftoneBlend,
        grainOpacity: grainOpacity + (other.grainOpacity - grainOpacity) * t,
        authBackdrop: authBackdrop.lerp(other.authBackdrop, t),
      );
    }
    return t < 0.5 ? this : other;
  }

  /// Convenience — grab NotifTokens from a BuildContext. Throws if the theme
  /// hasn't registered the extension (which is a programmer error: the App
  /// root must always install one).
  static NotifTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<NotifTokens>();
    if (tokens == null) {
      throw StateError(
        'NotifTokens extension missing from Theme. Did you forget to wrap '
        'MaterialApp with a theme built via buildNotifTheme()?',
      );
    }
    return tokens;
  }
}

typedef _TokenBuilder = NotifTokens Function();

/// Static registry of every shipped colorway. Adding a new colorway is a
/// two-step change: add the enum value, add the builder here. Both are
/// compile-time verified (enum exhaustiveness + the [NotifTokens.of] factory
/// throws on a missing registry entry).
class _NotifColorwayRegistry {
  const _NotifColorwayRegistry._();

  static final Map<NotifColorway, _TokenBuilder> tokens = {
    NotifColorway.dusk1: _buildDusk1,
    NotifColorway.dusk2: _buildDusk2,
    NotifColorway.midnight: _buildMidnight,
    NotifColorway.sage: _buildSage,
    NotifColorway.daybreak: _buildDaybreak,
  };

  // Each builder emits the tokens for a single colorway. When a colorway later
  // changes, update the corresponding builder in-place.
  static NotifTokens _buildDusk1() {
    return const NotifTokens(
      colorway: NotifColorway.dusk1,
      bg0: Color(0xFF0D0B0F),
      bg1: Color(0xFF16131A),
      bg2: Color(0xFF1E1A24),
      bg3: Color(0xFF2A2430),
      halo1: Color(0xFFFC2FA7),
      halo2: Color(0xFFCC33DE),
      halo3: Color(0xFF5D148F),
      ink: Color(0xFFE8E4E0),
      inkDim: Color(0xFFB0AAA3),
      inkMute: Color(0xFF706B65),
      inkFaint: Color(0x52E8E4E0),
      accent: Color(0xFFB89FD4),
      accent2: Color(0xFFE8A77A),
      rule: Color(0x24E8E4E0),
      ruleStrong: Color(0x47E8E4E0),
      btnBg: Color(0xFF6B3FA0),
      btnInk: Color(0xFFE8E4E0),
      btnBgAlt: Color(0x00000000),
      btnInkAlt: Color(0xFFB89FD4),
      halftone: Color(0xFF000000),
      halftoneBlend: BlendMode.multiply,
      grainOpacity: 0.24,
      authBackdrop: AuthBackdropColors(
        baseGradientColors: [
          Color(0xFF7716A4),
          Color(0xFF5D148F),
          Color(0xFF33104F),
          Color(0xFF0B0716),
          Color(0xFF000000),
        ],
        bloomColors: [
          Color(0xFFFC2FA7),
          Color(0xEEFA42B2),
          Color(0xA0CC33DE),
          Color(0x003E0D63),
        ],
        transitionColors: [
          Color(0x00FFFFFF),
          Color(0x44320D57),
          Color(0xAA09040F),
          Color(0xFF010103),
        ],
        floorFadeColors: [
          Color(0x00000000),
          Color(0xA6000000),
          Color(0xFF000000),
        ],
        grainFrom: Color(0xFF16040B),
        grainTo: Color(0xFF9A41DB),
        halftoneTop: Color(0xFF0A0219),
        halftoneBottom: Color(0xFF0A0219),
      ),
    );
  }

  static NotifTokens _buildDusk2() {
    return const NotifTokens(
      colorway: NotifColorway.dusk2,
      bg0: Color(0xFF0A0310),
      bg1: Color(0xFF1A0A26),
      bg2: Color(0xFF2D1244),
      bg3: Color(0xFF3A1A55),
      halo1: Color(0xFFFF2BB3),
      halo2: Color(0xFFB820CC),
      halo3: Color(0xFF4C1D95),
      ink: Color(0xFFF5E6FF),
      inkDim: Color(0xFFC9B0E0),
      inkMute: Color(0xFF8A7099),
      inkFaint: Color(0x59F5E6FF),
      accent: Color(0xFFFFB3E6),
      accent2: Color(0xFFFFD166),
      rule: Color(0x2EF5E6FF),
      ruleStrong: Color(0x59F5E6FF),
      btnBg: Color(0xFFF5E6FF),
      btnInk: Color(0xFF1A0A26),
      btnBgAlt: Color(0x00000000),
      btnInkAlt: Color(0xFFF5E6FF),
      halftone: Color(0xFF000000),
      halftoneBlend: BlendMode.multiply,
      grainOpacity: 0.28,
      authBackdrop: AuthBackdropColors(
        baseGradientColors: [
          Color(0xFF8C1771),
          Color(0xFF4C1D95),
          Color(0xFF2D1244),
          Color(0xFF14061F),
          Color(0xFF000000),
        ],
        bloomColors: [
          Color(0xFFFF2BB3),
          Color(0xEEF560C9),
          Color(0xA0B820CC),
          Color(0x004C1D95),
        ],
        transitionColors: [
          Color(0x00FFFFFF),
          Color(0x444C1D95),
          Color(0xAA16071F),
          Color(0xFF050108),
        ],
        floorFadeColors: [
          Color(0x00000000),
          Color(0xA6050108),
          Color(0xFF050108),
        ],
        grainFrom: Color(0xFF160828),
        grainTo: Color(0xFFFF64C8),
        halftoneTop: Color(0xFF040107),
        halftoneBottom: Color(0xFF040107),
      ),
    );
  }

  static NotifTokens _buildMidnight() {
    return const NotifTokens(
      colorway: NotifColorway.midnight,
      bg0: Color(0xFF030A12),
      bg1: Color(0xFF081624),
      bg2: Color(0xFF0F2438),
      bg3: Color(0xFF1A3350),
      halo1: Color(0xFF22D3EE),
      halo2: Color(0xFF0891B2),
      halo3: Color(0xFF164E63),
      ink: Color(0xFFD6EEF8),
      inkDim: Color(0xFF8FB6C5),
      inkMute: Color(0xFF5D7A87),
      inkFaint: Color(0x4DD6EEF8),
      accent: Color(0xFFFBBF24),
      accent2: Color(0xFF67E8F9),
      rule: Color(0x29D6EEF8),
      ruleStrong: Color(0x52D6EEF8),
      btnBg: Color(0xFFD6EEF8),
      btnInk: Color(0xFF081624),
      btnBgAlt: Color(0x00000000),
      btnInkAlt: Color(0xFFD6EEF8),
      halftone: Color(0xFF000000),
      halftoneBlend: BlendMode.multiply,
      grainOpacity: 0.30,
      authBackdrop: AuthBackdropColors(
        baseGradientColors: [
          Color(0xFF0E5A7A),
          Color(0xFF164E63),
          Color(0xFF0F2438),
          Color(0xFF030A12),
          Color(0xFF000000),
        ],
        bloomColors: [
          Color(0xFF22D3EE),
          Color(0xEE67E8F9),
          Color(0xA00891B2),
          Color(0x00164E63),
        ],
        transitionColors: [
          Color(0x00FFFFFF),
          Color(0x44164E63),
          Color(0xAA030A12),
          Color(0xFF000305),
        ],
        floorFadeColors: [
          Color(0x00000000),
          Color(0xA6000305),
          Color(0xFF000305),
        ],
        grainFrom: Color(0xFF061621),
        grainTo: Color(0xFF7DCB99),
        halftoneTop: Color(0xFF010408),
        halftoneBottom: Color(0xFF010408),
      ),
    );
  }

  static NotifTokens _buildSage() {
    return const NotifTokens(
      colorway: NotifColorway.sage,
      bg0: Color(0xFFE8E2C8),
      bg1: Color(0xFFDED7B8),
      bg2: Color(0xFFD2CAA6),
      bg3: Color(0xFFC5BC96),
      halo1: Color(0xFF8A9560),
      halo2: Color(0xFFA8B070),
      halo3: Color(0xFFC9CC8D),
      ink: Color(0xFF1A1C14),
      inkDim: Color(0xFF3A3D2A),
      inkMute: Color(0xFF5D5E42),
      inkFaint: Color(0x661A1C14),
      accent: Color(0xFF8A5A2A),
      accent2: Color(0xFF556832),
      rule: Color(0x381A1C14),
      ruleStrong: Color(0x801A1C14),
      btnBg: Color(0xFF1A1C14),
      btnInk: Color(0xFFE8E2C8),
      btnBgAlt: Color(0x00000000),
      btnInkAlt: Color(0xFF1A1C14),
      halftone: Color(0xFF1A1C14),
      halftoneBlend: BlendMode.multiply,
      grainOpacity: 0.22,
      authBackdrop: AuthBackdropColors(
        baseGradientColors: [
          Color(0xFFA8B070),
          Color(0xFFC9CC8D),
          Color(0xFFD2CAA6),
          Color(0xFFDED7B8),
          Color(0xFFE8E2C8),
        ],
        bloomColors: [
          Color(0xFFE8E2A8),
          Color(0xEEA8B070),
          Color(0xA08A9560),
          Color(0x00C9CC8D),
        ],
        transitionColors: [
          Color(0x00FFFFFF),
          Color(0x55C9CC8D),
          Color(0xAAD2CAA6),
          Color(0xFFE8E2C8),
        ],
        floorFadeColors: [
          Color(0x00E8E2C8),
          Color(0xA6D2CAA6),
          Color(0xFFE8E2C8),
        ],
        grainFrom: Color(0xFFE2DEBD),
        grainTo: Color(0xFF8A7C49),
        halftoneTop: Color(0xFF777565),
        halftoneBottom: Color(0xFF1A1C14),
      ),
    );
  }

  static NotifTokens _buildDaybreak() {
    return const NotifTokens(
      colorway: NotifColorway.daybreak,
      bg0: Color(0xFFE4EEF2),
      bg1: Color(0xFFD5E3EA),
      bg2: Color(0xFFC2D5DF),
      bg3: Color(0xFFA8C0CD),
      halo1: Color(0xFF0891B2),
      halo2: Color(0xFF0E5A7A),
      halo3: Color(0xFF164E63),
      ink: Color(0xFF071624),
      inkDim: Color(0xFF1E3A4D),
      inkMute: Color(0xFF4A6270),
      inkFaint: Color(0x66071624),
      accent: Color(0xFFA3550A),
      accent2: Color(0xFF0891B2),
      rule: Color(0x38071624),
      ruleStrong: Color(0x80071624),
      btnBg: Color(0xFF071624),
      btnInk: Color(0xFFE4EEF2),
      btnBgAlt: Color(0x00000000),
      btnInkAlt: Color(0xFF071624),
      halftone: Color(0xFF071624),
      halftoneBlend: BlendMode.multiply,
      grainOpacity: 0.20,
      authBackdrop: AuthBackdropColors(
        baseGradientColors: [
          Color(0xFF0E5A7A),
          Color(0xFF0891B2),
          Color(0xFFC2D5DF),
          Color(0xFFD5E3EA),
          Color(0xFFE4EEF2),
        ],
        bloomColors: [
          Color(0xFF67E8F9),
          Color(0xEE0891B2),
          Color(0xA00E5A7A),
          Color(0x00164E63),
        ],
        transitionColors: [
          Color(0x00FFFFFF),
          Color(0x55164E63),
          Color(0xAAC2D5DF),
          Color(0xFFE4EEF2),
        ],
        floorFadeColors: [
          Color(0x00E4EEF2),
          Color(0xA6C2D5DF),
          Color(0xFFE4EEF2),
        ],
        grainFrom: Color(0xFFBFD1D8),
        grainTo: Color(0xFF49786B),
        halftoneTop: Color(0xFF6A7781),
        halftoneBottom: Color(0xFF071624),
      ),
    );
  }
}
