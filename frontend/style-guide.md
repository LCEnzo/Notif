# Notif Design System

> **This document is the target design system, not a description of the
> current app.** Sections marked 🟢 reflect implemented code. Sections
> marked 🔶 are the redesign target. When the two conflict, the codebase
> is the source of truth for what exists; this doc is the source of truth
> for where we're going.

---

## 0. Aesthetic Intent

Five words that every design decision must pass through:

**Institutional. Secretive. Technical. Printed. Calm.**

Not playful. Not glossy. Not cute. Not maximalist.
The interface should feel like a declassified technical manual
printed on good paper — precise, warm, a little haunted.

When resolving an ambiguous decision, ask:
- Does this feel *printed* or does it feel like a screen? (prefer printed)
- Does this feel *calm* or does it feel energetic? (prefer calm)
- Does this feel *deliberate* or does it feel fluid? (prefer deliberate)
- Could I remove this element and lose nothing? (then remove it)

---

## 1. Palette Architecture

Two independent layers: **structural** (fixed) and **chromatic** (user-selectable).

### 1.1 Structural Layer (colorway-independent) 🔶

Defines the app's material quality. Never changes when the accent rotates.

| Token                | Hex (AARRGGBB)   | Role                                       |
| -------------------- | ---------------- | ------------------------------------------- |
| `struct.bg`          | `0xFF0D0B0F`     | Root scaffold. Warm near-black, not `#000`. |
| `struct.surface`     | `0xFF16131A`     | Cards, panels, sidebar. ~6% lighter than bg.|
| `struct.raised`      | `0xFF1E1A24`     | Elevated surfaces, dialogs.                 |
| `struct.text`        | `0xFFE8E4E0`     | Primary text. Warm off-white, not `#FFF`.   |
| `struct.text2`       | `0xFFB0AAA3`     | Secondary text, labels.                     |
| `struct.text3`       | `0xFF706B65`     | Hint, placeholder, disabled.                |
| `struct.border`      | `0xFF2A2630`     | 1px panel edges, card frames, rules.        |
| `struct.divider`     | `0xFF1F1B25`     | Faint section breaks.                       |

### 1.2 Chromatic Layer (accent) 🔶

Five token slots, populated by the active colorway.

| Token              | Role                                              |
| ------------------ | ------------------------------------------------- |
| `accent.primary`   | Primary actions, active nav, key affordances.      |
| `accent.muted`     | Hover states, subtle highlights, tags.             |
| `accent.dim`       | Focus rings, active borders, faint backgrounds.    |
| `accent.text`      | Accent-coloured text (links, active labels).       |
| `accent.onAccent`  | Text on filled accent surfaces.                    |

#### Preset Colorways

| Colorway         | `primary`  | `muted`    | `dim`      | `text`     |
| ---------------- | ---------- | ---------- | ---------- | ---------- |
| Violet (default) | `#6B3FA0`  | `#4A3070`  | `#2A1C45`  | `#B89FD4`  |
| Dusty Gold       | `#8C7A3E`  | `#6B5E30`  | `#3A3220`  | `#C4B06A`  |
| Pale Olive       | `#6B7A4E`  | `#4E5B3A`  | `#2A3020`  | `#A0B07A`  |
| Oxidized Teal    | `#4A7A72`  | `#365B56`  | `#1E3330`  | `#7EB0A6`  |
| Rust             | `#8C4A3A`  | `#6B3830`  | `#3A2020`  | `#C47A6A`  |

All presets use `struct.text` (`#E8E4E0`) as `accent.onAccent`.

Accents should feel muted and earned, never saturated or neon.
If it could be a gaming LED, desaturate it.

### 1.3 Auth Identity (fixed, not colorway-dependent) 🟢

| Token               | Value (AARRGGBB) | Source                    |
| -------------------- | ---------------- | ------------------------- |
| `auth.btnPrimary`    | `0xD14B22B5`     | `auth_palette.dart` ln 20 |
| `auth.btnSecondary`  | `0xD16339C2`     | `auth_palette.dart` ln 21 |
| `auth.btnBorder`     | `0x4DFFFFFF`     | `auth_palette.dart` ln 22 |
| `auth.panelFill`     | `0xFFE3E3E7` @ α0.2 | `auth_palette.dart`   |
| `auth.panelBorder`   | `0x29FFFFFF`     | `auth_palette.dart`       |
| `auth.panelShadow`   | `0x38000000`     | `auth_palette.dart`       |

> Previous drafts listed `auth.btnBorder` as `0x29FFFFFF`. The actual
> value in `auth_palette.dart` is `0x4DFFFFFF`. This has been corrected.

### 1.4 Feedback (fixed) 🔶

| Token              | Value (AARRGGBB) | Notes                                    |
| ------------------ | ---------------- | ---------------------------------------- |
| `feedback.error`   | `0xFFB04040`     | Muted red. Warning stamp, not LED.       |
| `feedback.success` | `0xFF5A8A5E`     | Desaturated sage green.                  |
| `feedback.warning` | `0xFFB09040`     | Dusty amber.                             |

---

## 2. Typography 🔶

Two typeface roles. One expressive, one utilitarian.

### 2.1 Font Assignments

| Role       | Primary Choice    | Fallback            | Source         |
| ---------- | ----------------- | ------------------- | -------------- |
| Display    | Instrument Serif  | Cormorant Garamond  | Google Fonts   |
| UI / Body  | Skyling           | Zalando Sans        | Google Fonts   |
| Mono       | Suisse Mono       | Hack Regular        | Swiss Typeface |

> **Current state 🟢:** The app names `'Hack Regular'` in `main.dart` but
> the font is not registered in `pubspec.yaml`. Either register it under
> `fonts:` or switch to the target fonts. Hack works as a fallback mono
> if Suisse Mono licensing is deferred.

### 2.2 Type Scale

| Level    | Face             | Size   | Weight   | Line Ht | Spacing  | Material Slot    | Use                           |
| -------- | ---------------- | ------ | -------- | ------- | -------- | ---------------- | ----------------------------- |
| Display  | Instrument Serif | `28dp` | Regular  | `36dp`  | `-0.5dp` | `displaySmall`   | Auth title, hero moments      |
| Headline | Instrument Serif | `22dp` | Regular  | `28dp`  | `0dp`    | `headlineSmall`  | Screen titles                 |
| Title    | Instrument Serif | `18dp` | Regular  | `24dp`  | `0dp`    | `titleLarge`     | Card titles, dialog titles    |
| Body     | Skyling          | `14dp` | Regular  | `20dp`  | `0.1dp`  | `bodyMedium`     | Default text, list items      |
| Label    | Skyling          | `11dp` | Medium   | `16dp`  | `1.2dp`  | `labelSmall`     | UPPERCASE. Tiny, tracked-out. |
| Caption  | Skyling          | `12dp` | Regular  | `16dp`  | `0.4dp`  | `bodySmall`      | Timestamps, helper text       |
| Code     | Suisse Mono      | `13dp` | Regular  | `18dp`  | `0dp`    | —                | Code snippets, mono contexts  |

### 2.3 Typography Rules

- Hero text: oversized, confident. Let it breathe.
- Labels: small, uppercase, letterspaced. Think classified-document
  section stamps: structural, not decorative.
- Body in a sans: constrain line width to ~70 characters max.
- Body in mono: constrain to ~60 characters.
- Hierarchy comes from typeface pairing and size, not colour blocks.
- Never use more than three font families (serif + sans + mono is the ceiling).

---

## 3. Spacing 🔶

Base unit: `4dp`.

| Token  | Value  | Use                                            |
| ------ | ------ | ---------------------------------------------- |
| `xs`   | `4dp`  | Icon-to-label gap                              |
| `sm`   | `8dp`  | Related elements                               |
| `md`   | `12dp` | Input internal padding                         |
| `base` | `16dp` | Content padding, field-to-field                |
| `lg`   | `24dp` | Section separation                             |
| `xl`   | `32dp` | Screen edge on auth, major breathing room      |
| `2xl`  | `48dp` | Hero vertical space, section breaks            |

This style needs air. Large empty areas are good. Dense detail
lives inside framed modules, not everywhere.

### Auth Overrides 🟢

| Context                  | Value  |
| ------------------------ | ------ |
| Auth card padding        | `28dp` |
| Auth field-to-field      | `16dp` |
| Auth screen edge         | `32dp` |

---

## 4. Shape 🔶

| Token         | Value  | Use                                              |
| ------------- | ------ | ------------------------------------------------ |
| `radius.none` | `0dp`  | **Default.** Buttons, cards, inputs, panels.     |
| `radius.sm`   | `4dp`  | Slight softening where 0 feels harsh.            |
| `radius.base` | `6dp`  | Auth glass surfaces only (card, tuner, buttons). |
| `radius.full` | `999dp`| Avatars.                                         |

> Default is rectangular. This is a deliberate departure from the
> current `6dp` everywhere approach. Auth keeps its radius; everything
> else goes flat.

---

## 5. Borders and Rules 🔶

Load-bearing design element. Where other styles use shadow and
elevation, this style uses **1px borders and thin rules**.

| Token              | Resolves To      | Width | Use                            |
| ------------------ | ---------------- | ----- | ------------------------------ |
| `border.rule`      | `struct.border`  | `1dp` | Panel edges, card frames       |
| `border.subtle`    | `struct.divider` | `1dp` | Faint section breaks           |
| `border.focus`     | `accent.dim`     | `2dp` | Focus rings on interactive el. |
| `border.error`     | `feedback.error` | `1dp` | Input error state              |
| `border.glass`     | `auth.panelBorder`| `1dp`| Auth glass surfaces only       |

**Rules:**
- No soft shadows. No `elevation`. No `BoxShadow` with blur.
- Panels are framed compartments, not floating cards.
- The glass recipe's shadow (auth only) is the sole exception.

---

## 6. Glass Surface Recipe 🟢

Auth-only. The one place translucency, blur, and shadow are permitted.

| Property | Value                                            |
| -------- | ------------------------------------------------ |
| Radius   | `radius.base` (`6dp`)                            |
| Fill     | `auth.panelFill`                                 |
| Border   | `auth.panelBorder`                               |
| Blur     | `ImageFilter.blur(sigmaX: 18, sigmaY: 18)`       |
| Shadow   | `auth.panelShadow`, blur `28dp`, Y offset `16dp` |

If a non-auth surface ever adopts glass, it reuses this recipe
exactly. No second translucent style.

---

## 7. Texture 🟢 (auth) / 🔶 (app-wide)

Texture is atmospheric, not decorative. Pick one primary type.

### Allowed

| Type              | Technique                             | Where                   |
| ----------------- | ------------------------------------- | ----------------------- |
| Film grain        | Noise overlay, fine 1px, low opacity  | Auth bg (🟢), scaffold (🔶) |
| Halftone / dither | Dot pattern or Floyd-Steinberg        | Images, hero areas (🔶) |
| Paper noise       | Scanned paper texture, very faint     | Surface backgrounds (🔶)|

### Intensity

| Context          | Opacity     |
| ---------------- | ----------- |
| Auth grain       | 0.3–0.5     |
| Non-auth grain   | 0.03–0.05   |

**Failure mode to avoid:** stacking grain + blur + glow + glitch + smoke.
One texture family per surface. If removing the texture makes the
screen feel empty, the layout is wrong.

### Auth Grain 🟢

| Property    | Value                                   |
| ----------- | --------------------------------------- |
| Colour ramp | `0xFF16040B` → `0xFF9A41DB`             |
| Blend mode  | `BlendMode.overlay` or `softLight`      |
| Density     | Fine, ~1px                              |

---

## 8. Component States 🔶

### 8.1 Buttons (default: outline/ghost)

| State    | Fill                          | Text              | Border            |
| -------- | ----------------------------- | ----------------- | ----------------- |
| Default  | transparent                   | `accent.text`     | `border.rule`     |
| Hover    | `accent.dim`                  | `accent.text`     | `accent.muted`    |
| Pressed  | `accent.muted`                | `accent.onAccent` | `accent.muted`    |
| Focused  | transparent                   | `accent.text`     | `border.focus` 2dp|
| Disabled | transparent                   | `struct.text3`    | `struct.divider`  |
| Loading  | transparent @ 0.5             | hidden            | unchanged + spinner|

Buttons: rectangular (`radius.none`), `1dp` border, compact height. No shadows.

### 8.2 Buttons (filled / primary CTA)

One per screen maximum.

| State    | Fill              | Text                | Border     |
| -------- | ----------------- | ------------------- | ---------- |
| Default  | `accent.primary`  | `accent.onAccent`   | none       |
| Hover    | `Color.lerp(accent.primary, struct.text, 0.08)` | unchanged | none |
| Pressed  | `Color.lerp(accent.primary, Color(0xFF000000), 0.12)` | unchanged | none |
| Focused  | `accent.primary`  | unchanged           | `border.focus` 2dp |
| Disabled | `struct.border`   | `struct.text3`      | none       |

### 8.3 Text Inputs

| State    | Border            | Label              | Fill                |
| -------- | ----------------- | ------------------ | ------------------- |
| Rest     | `border.rule`     | `struct.text2`     | transparent         |
| Focused  | `border.focus`    | `accent.text`      | transparent         |
| Error    | `border.error`    | `feedback.error`   | transparent         |
| Disabled | `struct.divider`  | `struct.text3`     | `struct.surface`    |

Flat, inset into the grid, no shadows. Error helper text: Caption
level in `feedback.error`, replacing any existing helper.

### 8.4 Panels / Cards

| State    | Background       | Border          |
| -------- | ---------------- | --------------- |
| Default  | `struct.surface` | `border.rule`   |
| Tapped   | `struct.raised`  | `accent.muted`  |
| Disabled | `struct.surface` | `struct.divider` |

Framed compartments. No floating. No shadow.

---

## 9. Iconography 🔶

### Primary Set: Material Sharp

Built into Flutter. Zero dependency. The Sharp variant has angular,
geometric quality aligned with the aesthetic.

Usage: `Icons.notifications_sharp`, `Icons.settings_sharp`, etc.

| Property       | Value                                     |
| -------------- | ----------------------------------------- |
| Default size   | `20dp` inline, `24dp` nav / appbar        |
| Colour         | Inherits text token for context           |

### Upgrade Path

If Material Sharp feels too generic for specific icons, replace
individual icons with custom SVGs or Pixelarticons. Don't mix full
icon sets — use Material Sharp as the base and override selectively.

---

## 10. Layout Principles 🔶

- Thin 1px border framing: outer page shell, panel edges, dividers.
- Rectangular modules. Generous margins. The style needs air.
- One dominant area per screen. Secondary info in a grid below.
- Asymmetry inside an ordered frame. Deliberate and architectural.
- Dense detail lives inside modules, not spread everywhere.
- Minimum text contrast: 4.5:1 (WCAG AA). Do not let the muted
  palette lower contrast to the point of illegibility.

### Imagery 🔶

When images are used:
- Monochrome or desaturated.
- Halftone, dithered, or thresholded processing.
- Treat images as degraded matter, not glossy illustration.
- No stock photography. No 3D blobs. No shiny gradients.

---

## 11. Motion 🔶

Sparse and slow. This style is calm.

- Fades: 200–400ms ease.
- Restrained hover states (opacity shift, border highlight).
- No spring physics. No bounce. No flashy entrances.
- Transitions feel like turning a page, not launching a rocket.

---

## 12. Screen Rules

### 12.1 Auth Screens 🟢

Auth retains its glass-forward identity. The one place translucency,
blur, and shadow are permitted.

- **Auth card:** glass recipe (§6). Text: `struct.text` / `struct.text2` / `struct.text3`.
- **Auth buttons:** `radius.base` (6dp, exception to rectangular default).
  Primary: `auth.btnPrimary`. Secondary: `auth.btnSecondary`. Border: `auth.btnBorder`.
  These do NOT rotate with colorway.
- **Auth background:** gradient `0xFF7716A4 → 0xFF5D148F → 0xFF33104F → 0xFF0B0716 → 0xFF000000`.
  Grain overlay per §7.

### 12.2 Non-Auth Screens 🔶

- **Scaffold:** `struct.bg`. Optional faint grain (0.03–0.05 opacity).
- **App bar:** `struct.surface`. 1px `border.rule` at bottom. No elevation. Title: Headline (Instrument Serif).
- **Cards / list items:** `struct.surface`, 1px `border.rule`, `radius.none`, `base` padding.
- **Empty states:** centred Body text in `struct.text2`. Optional muted icon (24dp, `struct.text3`).
- **Loading:** thin linear indicator in `accent.primary`. Skeleton: `struct.raised`, rectangular, pulsing 0.3–0.6 opacity.
- **Dialogs / bottom sheets:** `struct.raised`, `radius.sm` (4dp), 1px `border.rule`. No shadow. No glass.

---

## 13. Flutter Implementation 🔶

### 13.1 Colorway Model

```dart
// lib/theme/colorway.dart

import 'package:flutter/material.dart';

@immutable
class NotifColorway {
  final String name;
  final Color primary;
  final Color muted;
  final Color dim;
  final Color text;
  final Color onAccent;

  const NotifColorway({
    required this.name,
    required this.primary,
    required this.muted,
    required this.dim,
    required this.text,
    required this.onAccent,
  });

  // ── Presets ──

  static const violet = NotifColorway(
    name: 'Violet',
    primary:  Color(0xFF6B3FA0),
    muted:    Color(0xFF4A3070),
    dim:      Color(0xFF2A1C45),
    text:     Color(0xFFB89FD4),
    onAccent: Color(0xFFE8E4E0),
  );

  static const dustyGold = NotifColorway(
    name: 'Dusty Gold',
    primary:  Color(0xFF8C7A3E),
    muted:    Color(0xFF6B5E30),
    dim:      Color(0xFF3A3220),
    text:     Color(0xFFC4B06A),
    onAccent: Color(0xFFE8E4E0),
  );

  static const paleOlive = NotifColorway(
    name: 'Pale Olive',
    primary:  Color(0xFF6B7A4E),
    muted:    Color(0xFF4E5B3A),
    dim:      Color(0xFF2A3020),
    text:     Color(0xFFA0B07A),
    onAccent: Color(0xFFE8E4E0),
  );

  static const oxidizedTeal = NotifColorway(
    name: 'Oxidized Teal',
    primary:  Color(0xFF4A7A72),
    muted:    Color(0xFF365B56),
    dim:      Color(0xFF1E3330),
    text:     Color(0xFF7EB0A6),
    onAccent: Color(0xFFE8E4E0),
  );

  static const rust = NotifColorway(
    name: 'Rust',
    primary:  Color(0xFF8C4A3A),
    muted:    Color(0xFF6B3830),
    dim:      Color(0xFF3A2020),
    text:     Color(0xFFC47A6A),
    onAccent: Color(0xFFE8E4E0),
  );

  static const all = [violet, dustyGold, paleOlive, oxidizedTeal, rust];
}
```

### 13.2 Token System

```dart
// lib/theme/notif_tokens.dart

import 'package:flutter/material.dart';
import 'colorway.dart';

@immutable
class NotifTokens extends ThemeExtension<NotifTokens> {
  // ── Structural (fixed) ──
  final Color bg;
  final Color surface;
  final Color raised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color border;
  final Color divider;

  // ── Accent (from colorway) ──
  final Color accentPrimary;
  final Color accentMuted;
  final Color accentDim;
  final Color accentText;
  final Color accentOnAccent;

  // ── Feedback (fixed) ──
  final Color error;
  final Color success;
  final Color warning;

  // ── Shape (fixed) ──
  final double radiusNone;
  final double radiusSm;
  final double radiusBase;

  // ── Spacing (fixed) ──
  final double spaceXs;
  final double spaceSm;
  final double spaceMd;
  final double spaceBase;
  final double spaceLg;
  final double spaceXl;
  final double space2xl;

  // ── Borders (fixed) ──
  final double borderWidth;
  final double borderFocusWidth;

  // ── Glass (fixed, auth-only) ──
  final double glassBlur;
  final double glassShadowBlur;
  final double glassShadowOffsetY;

  const NotifTokens({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.border,
    required this.divider,
    required this.accentPrimary,
    required this.accentMuted,
    required this.accentDim,
    required this.accentText,
    required this.accentOnAccent,
    required this.error,
    required this.success,
    required this.warning,
    required this.radiusNone,
    required this.radiusSm,
    required this.radiusBase,
    required this.spaceXs,
    required this.spaceSm,
    required this.spaceMd,
    required this.spaceBase,
    required this.spaceLg,
    required this.spaceXl,
    required this.space2xl,
    required this.borderWidth,
    required this.borderFocusWidth,
    required this.glassBlur,
    required this.glassShadowBlur,
    required this.glassShadowOffsetY,
  });

  factory NotifTokens.fromColorway(NotifColorway cw) {
    return NotifTokens(
      // Structural
      bg:            const Color(0xFF0D0B0F),
      surface:       const Color(0xFF16131A),
      raised:        const Color(0xFF1E1A24),
      textPrimary:   const Color(0xFFE8E4E0),
      textSecondary: const Color(0xFFB0AAA3),
      textHint:      const Color(0xFF706B65),
      border:        const Color(0xFF2A2630),
      divider:       const Color(0xFF1F1B25),
      // Accent
      accentPrimary:  cw.primary,
      accentMuted:    cw.muted,
      accentDim:      cw.dim,
      accentText:     cw.text,
      accentOnAccent: cw.onAccent,
      // Feedback
      error:   const Color(0xFFB04040),
      success: const Color(0xFF5A8A5E),
      warning: const Color(0xFFB09040),
      // Shape
      radiusNone:  0,
      radiusSm:    4,
      radiusBase:  6,
      // Spacing
      spaceXs:  4,
      spaceSm:  8,
      spaceMd:  12,
      spaceBase: 16,
      spaceLg:  24,
      spaceXl:  32,
      space2xl: 48,
      // Borders
      borderWidth:      1,
      borderFocusWidth: 2,
      // Glass
      glassBlur:          18,
      glassShadowBlur:    28,
      glassShadowOffsetY: 16,
    );
  }

  // ── Convenience ──

  BorderSide get ruleSide => BorderSide(color: border, width: borderWidth);
  BorderSide get focusSide => BorderSide(color: accentDim, width: borderFocusWidth);
  BorderRadius get authRadius => BorderRadius.circular(radiusBase);
  BorderRadius get flatRadius => BorderRadius.circular(radiusNone);

  @override
  NotifTokens copyWith({
    Color? bg, Color? surface, Color? raised,
    Color? textPrimary, Color? textSecondary, Color? textHint,
    Color? border, Color? divider,
    Color? accentPrimary, Color? accentMuted, Color? accentDim,
    Color? accentText, Color? accentOnAccent,
    Color? error, Color? success, Color? warning,
    double? radiusNone, double? radiusSm, double? radiusBase,
    double? spaceXs, double? spaceSm, double? spaceMd,
    double? spaceBase, double? spaceLg, double? spaceXl, double? space2xl,
    double? borderWidth, double? borderFocusWidth,
    double? glassBlur, double? glassShadowBlur, double? glassShadowOffsetY,
  }) {
    return NotifTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentMuted: accentMuted ?? this.accentMuted,
      accentDim: accentDim ?? this.accentDim,
      accentText: accentText ?? this.accentText,
      accentOnAccent: accentOnAccent ?? this.accentOnAccent,
      error: error ?? this.error,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      radiusNone: radiusNone ?? this.radiusNone,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusBase: radiusBase ?? this.radiusBase,
      spaceXs: spaceXs ?? this.spaceXs,
      spaceSm: spaceSm ?? this.spaceSm,
      spaceMd: spaceMd ?? this.spaceMd,
      spaceBase: spaceBase ?? this.spaceBase,
      spaceLg: spaceLg ?? this.spaceLg,
      spaceXl: spaceXl ?? this.spaceXl,
      space2xl: space2xl ?? this.space2xl,
      borderWidth: borderWidth ?? this.borderWidth,
      borderFocusWidth: borderFocusWidth ?? this.borderFocusWidth,
      glassBlur: glassBlur ?? this.glassBlur,
      glassShadowBlur: glassShadowBlur ?? this.glassShadowBlur,
      glassShadowOffsetY: glassShadowOffsetY ?? this.glassShadowOffsetY,
    );
  }

  @override
  NotifTokens lerp(NotifTokens? other, double t) {
    if (other is! NotifTokens) return this;
    return NotifTokens(
      bg:             Color.lerp(bg,             other.bg, t)!,
      surface:        Color.lerp(surface,        other.surface, t)!,
      raised:         Color.lerp(raised,         other.raised, t)!,
      textPrimary:    Color.lerp(textPrimary,    other.textPrimary, t)!,
      textSecondary:  Color.lerp(textSecondary,  other.textSecondary, t)!,
      textHint:       Color.lerp(textHint,       other.textHint, t)!,
      border:         Color.lerp(border,         other.border, t)!,
      divider:        Color.lerp(divider,        other.divider, t)!,
      accentPrimary:  Color.lerp(accentPrimary,  other.accentPrimary, t)!,
      accentMuted:    Color.lerp(accentMuted,    other.accentMuted, t)!,
      accentDim:      Color.lerp(accentDim,      other.accentDim, t)!,
      accentText:     Color.lerp(accentText,     other.accentText, t)!,
      accentOnAccent: Color.lerp(accentOnAccent, other.accentOnAccent, t)!,
      error:          Color.lerp(error,          other.error, t)!,
      success:        Color.lerp(success,        other.success, t)!,
      warning:        Color.lerp(warning,        other.warning, t)!,
      radiusNone:     lerpDouble(radiusNone,     other.radiusNone, t)!,
      radiusSm:       lerpDouble(radiusSm,       other.radiusSm, t)!,
      radiusBase:     lerpDouble(radiusBase,     other.radiusBase, t)!,
      spaceXs:        lerpDouble(spaceXs,        other.spaceXs, t)!,
      spaceSm:        lerpDouble(spaceSm,        other.spaceSm, t)!,
      spaceMd:        lerpDouble(spaceMd,        other.spaceMd, t)!,
      spaceBase:      lerpDouble(spaceBase,      other.spaceBase, t)!,
      spaceLg:        lerpDouble(spaceLg,        other.spaceLg, t)!,
      spaceXl:        lerpDouble(spaceXl,        other.spaceXl, t)!,
      space2xl:       lerpDouble(space2xl,       other.space2xl, t)!,
      borderWidth:    lerpDouble(borderWidth,    other.borderWidth, t)!,
      borderFocusWidth: lerpDouble(borderFocusWidth, other.borderFocusWidth, t)!,
      glassBlur:      lerpDouble(glassBlur,      other.glassBlur, t)!,
      glassShadowBlur: lerpDouble(glassShadowBlur, other.glassShadowBlur, t)!,
      glassShadowOffsetY: lerpDouble(glassShadowOffsetY, other.glassShadowOffsetY, t)!,
    );
  }
}

// ── Usage ──
//
// final cw = NotifColorway.violet; // or user's saved preference
// final t = NotifTokens.fromColorway(cw);
//
// MaterialApp(
//   theme: ThemeData(
//     brightness: Brightness.dark,
//     scaffoldBackgroundColor: t.bg,
//     extensions: [t],
//     textTheme: notifTextTheme(),
//   ),
// )
//
// In widgets:
//   final t = Theme.of(context).extension<NotifTokens>()!;
//   Container(
//     padding: EdgeInsets.all(t.spaceBase),
//     decoration: BoxDecoration(
//       color: t.surface,
//       border: Border.all(color: t.border, width: t.borderWidth),
//       borderRadius: t.flatRadius,
//     ),
//   )
```

### 13.3 TextTheme

```dart
// lib/theme/notif_text_theme.dart

import 'package:flutter/material.dart';

const _display = 'InstrumentSerif';
const _body    = 'ZalandoSans';  // or 'Skyling'
const _mono    = 'SuisseMono';   // fallback: 'Hack'

TextTheme notifTextTheme() {
  return const TextTheme(
    // Serif display
    displaySmall:  TextStyle(fontFamily: _display, fontSize: 28, fontWeight: FontWeight.w400, height: 36 / 28, letterSpacing: -0.5),
    headlineSmall: TextStyle(fontFamily: _display, fontSize: 22, fontWeight: FontWeight.w400, height: 28 / 22, letterSpacing: 0),
    titleLarge:    TextStyle(fontFamily: _display, fontSize: 18, fontWeight: FontWeight.w400, height: 24 / 18, letterSpacing: 0),
    // Sans body
    bodyMedium:    TextStyle(fontFamily: _body, fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14, letterSpacing: 0.1),
    labelSmall:    TextStyle(fontFamily: _body, fontSize: 11, fontWeight: FontWeight.w500, height: 16 / 11, letterSpacing: 1.2),
    bodySmall:     TextStyle(fontFamily: _body, fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, letterSpacing: 0.4),
    // labelLarge for buttons
    labelLarge:    TextStyle(fontFamily: _body, fontSize: 14, fontWeight: FontWeight.w500, height: 20 / 14, letterSpacing: 0.1),
  );
}
```

---

## 14. Build Priority

Implement in this order. Each step is independently shippable.

| # | Change                        | Effort  | Impact                              |
|---|-------------------------------|---------|--------------------------------------|
| 1 | Warm structural palette       | Low     | Replace any `#000`/`#FFF`. Instant feel shift. |
| 2 | Add Instrument Serif          | Low     | Use for screen titles. Single biggest aesthetic change. |
| 3 | Replace elevation with 1px rules | Medium | Remove `BoxShadow`, add `Border.all(color: border, width: 1)`. |
| 4 | Flatten radii to 0 (non-auth) | Low     | Set default to rectangular.          |
| 5 | Faint scaffold grain          | Low     | Extend auth grain to bg at 0.03–0.05 opacity. |
| 6 | Wire `NotifTokens` extension  | Medium  | Enables colorway switching.          |
| 7 | Colorway picker in settings   | Medium  | Store in SharedPreferences, rebuild theme. |
| 8 | Material Sharp icon audit     | Low     | Replace any remaining default icons.  |

Everything else (full state coverage, Suisse Mono integration,
halftone image processing) is polish after the foundation is laid.
