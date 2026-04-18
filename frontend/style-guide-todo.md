# Notif Design System — Evolution Spec

**Status:** working specification. Written 2026-04 after comparing the current
`style-guide.md` (narrative of intent) with the `design experiment/` React
sketches. Captures the direction, the decisions, the dropped alternatives, and
enough detail that implementation doesn't need to re-derive anything.

When a section here lands in code, promote its final form to `style-guide.md`
and delete the implemented section from this file. This doc drains over time
into the proper reference.

---

## 0. Purpose of the document

The current `style-guide.md` reads as a mood piece: five words, a few target
tables, a rough build priority. Useful for alignment, insufficient for
building. A proper design system is a **reference**: exhaustive token tables,
named primitives with state specs, recipes, usage rules, screen patterns.

This doc is the target. `style-guide.md` becomes it once implementation
catches up.

---

## 1. Aesthetic intent (unchanged)

**Institutional. Secretive. Technical. Printed. Calm.**

Every visual decision passes through:

- Does this feel *printed* or does it feel like a screen? (prefer printed)
- Does this feel *calm* or does it feel energetic? (prefer calm)
- Does this feel *deliberate* or does it feel fluid? (prefer deliberate)
- Could I remove this element and lose nothing? (then remove it)

What's rejected by name: playful, glossy, cute, bouncy, 3D, saturated-neon,
spring-physics, motion for its own sake, stock photography, rounded plastic,
floating shadows.

---

## 2. Two-layer palette

All visual surfaces split into two layers:

**Structural layer** — depth, text, rules. Defined per colorway but shares a
shape: four bg steps, four ink steps, two rule strengths. This layer is about
*how readable and how deep* a surface is.

**Chromatic layer** — halo (atmospheric), accent (action), accent2
(counterweight). This is what gives each colorway its name and mood.

**Texture layer** — halftone color, blend mode, baseline grain opacity.
Intensity scales multiplicatively via a debug-tuner dial.

**Interactive layer** — button background / ink pair, plus the alternate
(ghost) pair. Derived from ink + background, not from accent.

This maps to the token namespace in §3.

---

## 3. Token namespace

Every colorway defines all tokens. No fallbacks: if a colorway ships, it
declares values for everything listed below. Missing values are a colorway
bug, not a design system escape hatch.

### 3.1 Token table

| Token            | Type               | Purpose                                                    |
| ---------------- | ------------------ | ---------------------------------------------------------- |
| `bg0`            | solid color        | Void. Beyond the scaffold. Floor of the signature backdrop. |
| `bg1`            | solid color        | Scaffold. Default page background.                          |
| `bg2`            | solid color        | Cards, panels, raised surfaces.                             |
| `bg3`            | solid color        | Dialogs, menus, second-level raised.                        |
| `halo1`          | solid color        | Brightest atmospheric color — halo core. Signature backdrop only. |
| `halo2`          | solid color        | Mid atmospheric color — halo rim.                           |
| `halo3`          | solid color        | Outermost atmospheric color — transitions into bg1.         |
| `ink`            | solid color        | Primary text.                                               |
| `inkDim`         | solid color        | Secondary text, labels.                                     |
| `inkMute`        | solid color        | Hints, placeholders, disabled text, micro-mono meta.        |
| `inkFaint`       | alpha'd ink        | Decorative subduction of ink (unread-dots, faded tags).     |
| `accent`         | solid color        | Action color. Bright enough to read on bg1. Not a neon.     |
| `accent2`        | solid color        | Counterweight. Used when accent would be tautological.      |
| `rule`           | alpha'd ink        | Faint hairlines: dashed KV rules, item dividers, tag borders. |
| `ruleStrong`     | alpha'd ink        | Definite hairlines: card borders, AppBar underline, input underlines. |
| `btnBg`          | solid color        | Primary button fill (usually = ink on dark, inverse on light). |
| `btnInk`         | solid color        | Primary button text (usually = bg1).                        |
| `btnBgAlt`       | color / transparent | Ghost button fill (always `transparent`).                 |
| `btnInkAlt`      | solid color        | Ghost button text (usually = ink).                          |
| `halftone`       | solid color        | Halftone dot color. Usually `#000` on dark, `ink` on light. |
| `halftoneBlend`  | blend mode         | Usually `multiply`.                                         |
| `grainOpacity`   | 0–1 scalar         | Baseline grain strength. Multiplied by texture-dial value.  |
| `scheme`         | `'dark'` \| `'light'` | Drives Flutter's `Brightness` and tone curves elsewhere. |

### 3.2 Rule tokens: translucent, not opaque

The current code uses opaque colors (`structBorder: #2A2630`) for rules. The
experiment uses alpha'd ink (`rgba(245,230,255,0.18)`). The alpha approach
composites correctly on any background — including the halo gradient and
halftone dots. **Translucent is the rule.** When porting, convert any opaque
border value into `ink` with alpha.

### 3.3 Migration: old → new

| Old (`NotifDesignTokens` / `AuthPalette`)       | New                             |
| ----------------------------------------------- | ------------------------------- |
| `structBg`                                      | `bg0`                           |
| `structSurface`                                 | `bg1`                           |
| `structRaised`                                  | `bg2`                           |
| —                                               | `bg3` (new, one step above bg2) |
| `structText`                                    | `ink`                           |
| `structText2`                                   | `inkDim`                        |
| `structText3`                                   | `inkMute`                       |
| `structBorder`                                  | `ruleStrong` (as alpha'd ink)   |
| `structDivider`                                 | `rule` (as alpha'd ink)         |
| `accentPrimary`                                 | `btnBg` (for Dusk 1)            |
| `accentMuted`                                   | *(derived at runtime; retired)* |
| `accentDim`                                     | *(used for focus; retired)*     |
| `accentText`                                    | `accent`                        |
| `accentOnAccent`                                | `btnInk`                        |
| `AuthPalette.bloomColors[0..2]`                 | `halo1`, `halo2`, `halo3`       |
| `AuthPalette.grainFrom/grainTo`                 | *(replaced by `halftone` + `feTurbulence` params)* |

---

## 4. Shipping colorway roster

Five entries. Three dark, two light. Every entry lists all tokens from §3.1.

| #  | Name         | Scheme | Mood                                         |
| -- | ------------ | ------ | -------------------------------------------- |
| 01 | **Dusk 1**   | dark   | Default. Warm violet. Current app identity.  |
| 02 | **Dusk 2**   | dark   | Hotter magenta-pink. Harder edge.            |
| 03 | **Midnight** | dark   | Radio static in the ocean trench.            |
| 04 | **Sage**     | light  | Aged paper and cactus. Urbit field journal.  |
| 05 | **Daybreak** | light  | Coastal daylight. Counterpart to Midnight.   |

### 4.1 Dusk 1 — default

Derived from current `NotifDesignTokens` + `AuthPalette`. `bg3`, `halo*`,
`accent2`, `inkFaint`, alpha'd rules are new — chosen to fit the existing
palette rather than introduced arbitrarily.

```
bg0             #0D0B0F
bg1             #16131A
bg2             #1E1A24
bg3             #2A2430
halo1           #FC2FA7   (from AuthPalette bloom[0])
halo2           #CC33DE   (from AuthPalette bloom[2])
halo3           #5D148F   (from AuthPalette baseGradient[1])
ink             #E8E4E0
inkDim          #B0AAA3
inkMute         #706B65
inkFaint        rgba(232,228,224,0.32)
accent          #B89FD4   (was accentText)
accent2         #E8A77A   (warm sand counterweight — new)
rule            rgba(232,228,224,0.14)
ruleStrong      rgba(232,228,224,0.28)
btnBg           #6B3FA0   (was accentPrimary)
btnInk          #E8E4E0
btnBgAlt        transparent
btnInkAlt       #B89FD4
halftone        #000000
halftoneBlend   multiply
grainOpacity    0.24
scheme          dark
```

### 4.2 Dusk 2

Verbatim from experiment `dusk.dark`.

```
bg0             #0A0310
bg1             #1A0A26
bg2             #2D1244
bg3             #3A1A55
halo1           #FF2BB3
halo2           #B820CC
halo3           #4C1D95
ink             #F5E6FF
inkDim          #C9B0E0
inkMute         #8A7099
inkFaint        rgba(245,230,255,0.35)
accent          #FFB3E6
accent2         #FFD166
rule            rgba(245,230,255,0.18)
ruleStrong      rgba(245,230,255,0.35)
btnBg           #F5E6FF
btnInk          #1A0A26
btnBgAlt        transparent
btnInkAlt       #F5E6FF
halftone        #000000
halftoneBlend   multiply
grainOpacity    0.28
scheme          dark
```

### 4.3 Midnight

Verbatim from experiment `cyan.dark`. Amber accent is deliberate — a warm
signal against cold water.

```
bg0             #030A12
bg1             #081624
bg2             #0F2438
bg3             #1A3350
halo1           #22D3EE
halo2           #0891B2
halo3           #164E63
ink             #D6EEF8
inkDim          #8FB6C5
inkMute         #5D7A87
inkFaint        rgba(214,238,248,0.30)
accent          #FBBF24
accent2         #67E8F9
rule            rgba(214,238,248,0.16)
ruleStrong      rgba(214,238,248,0.32)
btnBg           #D6EEF8
btnInk          #081624
btnBgAlt        transparent
btnInkAlt       #D6EEF8
halftone        #000000
halftoneBlend   multiply
grainOpacity    0.30
scheme          dark
```

### 4.4 Sage

Verbatim from experiment `sage.light`. First light-mode colorway.

```
bg0             #E8E2C8
bg1             #DED7B8
bg2             #D2CAA6
bg3             #C5BC96
halo1           #8A9560
halo2           #A8B070
halo3           #C9CC8D
ink             #1A1C14
inkDim          #3A3D2A
inkMute         #5D5E42
inkFaint        rgba(26,28,20,0.40)
accent          #8A5A2A
accent2         #556832
rule            rgba(26,28,20,0.22)
ruleStrong      rgba(26,28,20,0.50)
btnBg           #1A1C14
btnInk          #E8E2C8
btnBgAlt        transparent
btnInkAlt       #1A1C14
halftone        #1A1C14
halftoneBlend   multiply
grainOpacity    0.22
scheme          light
```

### 4.5 Daybreak

Verbatim from experiment `cyan.light`. Name chosen to pair with Midnight —
open to change. Alternates considered: Harbor, Tideline, Mariner, Shoreline,
Foreshore.

```
bg0             #E4EEF2
bg1             #D5E3EA
bg2             #C2D5DF
bg3             #A8C0CD
halo1           #0891B2
halo2           #0E5A7A
halo3           #164E63
ink             #071624
inkDim          #1E3A4D
inkMute         #4A6270
inkFaint        rgba(7,22,36,0.40)
accent          #A3550A
accent2         #0891B2
rule            rgba(7,22,36,0.22)
ruleStrong      rgba(7,22,36,0.50)
btnBg           #071624
btnInk          #E4EEF2
btnBgAlt        transparent
btnInkAlt       #071624
halftone        #071624
halftoneBlend   multiply
grainOpacity    0.20
scheme          light
```

---

## 5. Parked colorways

Not shipping in the initial roster, but kept in the spec so the colors aren't
lost. Each needs token-set completion before it can be activated (halo triad,
accent2, texture parameters).

### 5.1 From v1 guide — accent-only entries

These only have primary / muted / dim / text values from the original guide.
If adopted, they'd borrow structural tokens from a matching scheme (Dusk 1
structure for dark variants, Sage structure for light variants), add halo
and accent2 values, and pick a `grainOpacity`.

| Name             | primary (→ btnBg) | muted     | dim       | text (→ accent) |
| ---------------- | ----------------- | --------- | --------- | --------------- |
| **Dusty Gold**   | `#8C7A3E`         | `#6B5E30` | `#3A3220` | `#C4B06A`       |
| **Pale Olive**   | `#6B7A4E`         | `#4E5B3A` | `#2A3020` | `#A0B07A`       |
| **Oxidized Teal**| `#4A7A72`         | `#365B56` | `#1E3330` | `#7EB0A6`       |
| **Rust**         | `#8C4A3A`         | `#6B3830` | `#3A2020` | `#C47A6A`       |

All were intended as dark-mode colorways in the v1 guide, using
`#E8E4E0` as `accentOnAccent` (maps to `btnInk`).

### 5.2 From the experiment — full token sets

Preserved in case the Library aesthetic or a dark-Sage variant becomes
desirable. Verbatim from `design experiment/tokens.jsx`.

**Library (dark)** — library binding rendered as dark mode, warm cream body
on deep teal, warm counterweight accent.

```
bg0  #071914   bg1  #0C2823   bg2  #133A32   bg3  #1F4A42
halo1 #4A8A7A  halo2 #2A5A50  halo3 #0C2823
ink   #E6DCC5  inkDim #B8AE97 inkMute #7A8882  inkFaint rgba(230,220,197,0.32)
accent #D4B07A accent2 #8AA59A
rule  rgba(230,220,197,0.16)  ruleStrong rgba(230,220,197,0.32)
btnBg #E6DCC5  btnInk #0C2823
halftone #000  halftoneBlend multiply  grainOpacity 0.30  scheme dark
```

**Library (light)** — warm cream paper.

```
bg0  #F0E8CF   bg1  #E6DCC5   bg2  #DCCF9F   bg3  #C9BA82
halo1 #1F4A42  halo2 #4A8A7A  halo3 #8AA59A
ink   #0C2823  inkDim #2A5046 inkMute #5D6E68  inkFaint rgba(12,40,35,0.40)
accent #8A5A2A accent2 #1F4A42
rule  rgba(12,40,35,0.22)  ruleStrong rgba(12,40,35,0.50)
btnBg #0C2823  btnInk #E6DCC5
halftone #0C2823  halftoneBlend multiply  grainOpacity 0.20  scheme light
```

**Sage (dark)** — dark counterpart to the shipped Sage light.

```
bg0  #0E0F0A   bg1  #1A1C14   bg2  #22261B   bg3  #2D3325
halo1 #C9CC8D  halo2 #8A9560  halo3 #3A4528
ink   #E8E4CC  inkDim #B8B494 inkMute #7D7A5F  inkFaint rgba(232,228,204,0.32)
accent #D4A05A accent2 #A8B070
rule  rgba(232,228,204,0.18)  ruleStrong rgba(232,228,204,0.35)
btnBg #E8E4CC  btnInk #1A1C14
halftone #000  halftoneBlend multiply  grainOpacity 0.32  scheme dark
```

**Dusk (light)** — light counterpart to the shipped Dusk entries. Distinct
from Dusk 1 / Dusk 2 — a separate color.

```
bg0  #EDE6EF   bg1  #E0D4E2   bg2  #D1C0D4   bg3  #C1A8C6
halo1 #C94DA1  halo2 #8A4DC9  halo3 #6A3C9A
ink   #2A0C2E  inkDim #4A2650 inkMute #6B4A72  inkFaint rgba(42,12,46,0.40)
accent #8A2075 accent2 #C96A1A
rule  rgba(42,12,46,0.22)  ruleStrong rgba(42,12,46,0.50)
btnBg #2A0C2E  btnInk #EDE6EF
halftone #2A0C2E  halftoneBlend multiply  grainOpacity 0.20  scheme light
```

---

## 6. Typography

Three selectable **font sets**. Each set is a complete `TextTheme`. The user
picks one in Settings; the app rebuilds the theme on change.

The experiment defines an 8-role scale (`display`, `title`, `heading`,
`eyebrow`, `body`, `bodyLong`, `micro`, `code`). The current app uses a
narrower 6-role scale (`display`, `headline`, `title`, `body`, `label`,
`caption`, plus `mono`). The Experiment and Hybrid sets use the 8-role scale;
the Current set preserves the existing 6-role scale exactly.

### 6.1 Role scale — 8-role (Experiment + Hybrid sets)

| Role       | Size  | Line ht | Tracking  | Case      | Role family  |
| ---------- | ----- | ------- | --------- | --------- | ------------ |
| display    | 64    | 0.95    | −0.02em   | mixed     | serif        |
| title      | 40    | 1.02    | −0.015em  | mixed     | serif        |
| heading    | 22    | 1.15    | −0.01em   | mixed     | serif        |
| eyebrow    | 11    | 1.0     | +0.20em   | UPPER     | mono         |
| body       | 13    | 1.5     | 0         | mixed     | mono         |
| bodyLong   | 15    | 1.55    | 0         | mixed     | serifLong    |
| micro      | 10.5  | 1.3     | +0.12em   | UPPER     | mono         |
| code       | 12    | 1.5     | 0         | mixed     | mono         |

### 6.2 Role scale — Current set (6-role, existing)

Preserved from `NotifDesignTokens` + the duplicated styles in `settings.dart`
/ `about.dart`. Fix the current drift (`_titleStyle` is 20sp in Settings,
26sp in About) by picking 22sp as canonical and extracting the styles to a
shared file.

| Role     | Size | Line ht | Tracking | Weight | Family         |
| -------- | ---- | ------- | -------- | ------ | -------------- |
| display  | 34   | 42/34   | −0.5     | 400    | serif          |
| headline | 24   | 30/24   | 0        | 400    | serif          |
| title    | 22   | 28/22   | 0        | 400    | serif          |
| body     | 15   | 22/15   | +0.1     | 400    | sans (body)    |
| label    | 12   | 16/12   | +1.2     | 500    | sans (body)    |
| caption  | 13   | 18/13   | 0        | 400    | sans (body)    |
| mono     | 14   | 20/14   | 0        | 400    | mono           |

### 6.3 Font sets

| Role            | Current set       | Experiment set   | Hybrid set (exp roles, current fonts) |
| --------------- | ----------------- | ---------------- | -------------------------------------- |
| *all serif*     | Instrument Serif  | Instrument Serif | Instrument Serif                       |
| *serif (long)*  | —                 | Newsreader       | Instrument Serif (italic)              |
| *body / mono*   | Skyling           | JetBrains Mono   | Suisse Mono                            |
| *utility sans*  | Zalando Sans      | Inter Tight      | Skyling                                |
| *mono (code)*   | Suisse Mono       | JetBrains Mono   | Suisse Mono                            |

Notes:

- **Current set** maps its 6 roles with Instrument Serif (serif), Skyling
  (body/label/caption), Suisse Mono (mono). No `eyebrow` / `bodyLong` /
  `micro` distinctions — code that tries to use those roles under the Current
  set falls back to `label` (for `eyebrow`/`micro`) or `body` (for `bodyLong`).
- **Experiment set** uses the 8-role scale with Instrument Serif, Newsreader
  (body-length serif for digests and long-form reads), JetBrains Mono (body
  + micro + code), Inter Tight (utility sans, unused by default).
- **Hybrid set** uses the 8-role scale but keeps the current paid-license
  fonts: Instrument Serif stays, Suisse Mono covers all mono roles, Skyling
  is the utility sans. `bodyLong` resolves to **Instrument Serif italic** —
  there's no serif body face in the current set, so long reads get the
  display serif slowed down with italic. If this doesn't work in practice,
  fall back to Skyling.

### 6.4 Rules

- Max three families per surface.
- Hierarchy comes from typeface pairing and size, not color blocks.
- Body lines in mono cap at ~60 characters. In serif, ~70. In sans, ~75.
- Eyebrow / micro labels are always uppercase with wide tracking — structural,
  not decorative.
- Display and title sizes are deliberately oversized; let them breathe. If
  you need to shrink them to fit, the layout is wrong.
- Never use `FontStyle.italic` for the Current set's `bodyLong` — it doesn't
  apply there. Italic-for-emphasis belongs to Instrument Serif specifically.

### 6.5 Default font set

**Current** on first run. Flipping the default to Experiment happens once
Home/Feed/Empty are redesigned against the 8-role scale.

### 6.6 `pubspec.yaml` registration

Keep the current entries (Instrument Serif, Skyling, Zalando Sans,
Suisse Mono). Add the experiment fonts (Newsreader, JetBrains Mono,
Inter Tight). All three sets coexist in the bundled app; the switcher just
picks which one to wire into the TextTheme.

---

## 7. Shape, spacing, motion

### 7.1 Shape

Corners are rectangular by default. The `6dp` auth-glass exception stays.
Nothing else gets radius.

| Token      | Value | Use                                                    |
| ---------- | ----- | ------------------------------------------------------ |
| `rNone`    | 0     | Default everywhere outside auth.                       |
| `rSm`      | 4     | Rare softening where 0 looks broken (dialogs, toasts). |
| `rAuth`    | 6     | Auth card, auth tuner, auth buttons only.              |
| `rFull`    | 999   | Avatars.                                               |

No `BoxShadow`, no `elevation`. The glass recipe's shadow (§9) is the sole
exception, auth-only.

### 7.2 Spacing

Base 4dp.

| Token   | Value | Use                                         |
| ------- | ----- | ------------------------------------------- |
| `xs`    | 4     | Icon-to-label gap                           |
| `sm`    | 8     | Related elements                            |
| `md`    | 12    | Input internal padding                      |
| `base`  | 16    | Content padding, field-to-field             |
| `lg`    | 24    | Section separation                          |
| `xl`    | 32    | Screen edge on auth, major breathing room   |
| `2xl`   | 48    | Hero vertical space, section breaks         |

Auth screens override to `28` padding internally, `32` at the edge.

### 7.3 Motion

| Stage       | Duration | Curve     |
| ----------- | -------- | --------- |
| micro       | 110 ms   | easeOut   |
| short       | 180 ms   | easeOut   |
| page        | 220 ms   | easeOutCubic |
| fade (long) | 400 ms   | easeInOut |

No springs, no bounces, no overshoot. Transitions feel like turning a page.

---

## 8. Borders and rules

One design move does most of the work: **hairlines carry elevation**. Where
other systems use shadow, this one uses 1px.

| Name         | Token          | Width | Use                                         |
| ------------ | -------------- | ----- | ------------------------------------------- |
| rule         | `rule`         | 1     | Faint dividers (KV rows, item dividers)     |
| ruleStrong   | `ruleStrong`   | 1     | Card borders, AppBar bottom, input underline |
| focus        | `accent`       | 2     | Focus rings on interactive elements         |
| error        | `feedback.error` | 1   | Input error state                           |
| dashed       | `rule`         | 1     | KV rows specifically — signals "form"       |

Dashed rules are a concrete visual move, not an afterthought. They mark rows
that read as **form fields** or **ledger lines** rather than paragraph breaks.

---

## 9. Signature backdrop (recipe)

The atmospheric environment from the experiment. Non-auth only. Auth keeps
its own hand-tuned pipeline (gradient + bloom + grain + dither + CustomPaint).

### 9.1 Layers

**Layer A — halo gradient.** Radial, ellipse `60% × haloHeight` centered at
`50% 0%` (top-center).

```
stop 0%   halo1
stop 30%  halo2
stop 55%  halo3
stop 78%  bg1
stop 100% bg0
```

`haloHeight` default: 55% of surface height on desktop, 45% on mobile.

**Layer B — grain.** Two SVG `feTurbulence` passes stacked.

| Pass | baseFrequency | numOctaves | contrast | blend    | opacity               |
| ---- | ------------- | ---------- | -------- | -------- | --------------------- |
| 1    | 0.9           | 2          | 140%     | overlay  | 0.35 × (texture / 10) |
| 2    | 2.5           | 2          | 180%     | multiply | 0.18 × (texture / 10) |

`stitchTiles="stitch"` on both. Seed is fixed per render so grain doesn't
shimmer across frames.

**Layer C — curved halftone floor.** 28 rows of dots along the bottom of
the surface.

- Row spacing: `height / 28`
- Dot spacing within a row: 8px (every other row offset by 4px for hex pack)
- Dot radius: `0.4` at the top of the floor, linearly increasing to `2.6` at
  the bottom
- Visibility cutoff: cosine curve `cos((x − centerX) / 800) × 30 + 12` —
  dots only render *below* this curve, giving the curved top edge
- Fill: `halftone` token
- Blend: `halftoneBlend` token
- Default floor height: 260dp (desktop), 200dp (mobile)

### 9.2 Intensity

Each layer's opacity multiplies by `texture / 10` where `texture` is the
debug-tuner dial (0..10). At `0`, the three layers are fully invisible and
the surface is flat `bg0`. At `10`, full recipe.

Default for non-auth screens: `texture = 4`. Tune up from there per screen.

### 9.3 Flutter port considerations

- Halo: `Container` with a `RadialGradient` decoration. No shader needed.
- Grain: two stacked `CustomPaint` widgets. Use a pre-rendered noise
  `Image` (bake a 512×512 grayscale at build-time) rather than re-deriving
  turbulence per frame. The existing `DitherOverlay` can be the base.
- Halftone: `CustomPaint` drawing circles into a `Path` clipped by the
  cosine curve. Pre-compute the dot list per `(height, intensity)` pair.

### 9.4 Usage rules

- Auth: **not applied**.
- Scaffold background on empty states, auth landing replacement (if
  reconsidered later), hero pages.
- Never stacked inside a card. Only at the scaffold level.
- If a surface uses the signature backdrop, it takes no additional grain,
  halftone, or dither layers — the backdrop is the full texture budget.

---

## 10. Texture dial (debug tuner, not Settings)

Texture intensity is a debugging concern, not a user-facing preference. It
lives in the existing auth debug tuner (currently used for auth-card swap),
extended with new controls.

### 10.1 Controls to add to the debug tuner

- **Colorway picker** — mirror of the Settings picker, for previewing
  colorways from auth before the app is entered.
- **Scheme toggle** — dark / light (only available schemes light up).
- **Font set picker** — Current / Experiment / Hybrid.
- **Texture intensity slider** — 0..10, default 4 on non-auth surfaces.
- **Signature backdrop toggle** — show / hide on the current route.
- **Individual layer toggles** — halo / grain (pass 1) / grain (pass 2) /
  halftone, so visual bugs can be isolated.

### 10.2 User-facing Settings

Only stable, user-meaningful controls:

- Colorway picker
- Scheme toggle (where applicable)
- Font set picker
- Backend URL (existing)

Everything else is tuner territory.

---

## 11. Component catalog

Named primitives. Each lists purpose, anatomy, states, usage rules, and
forbidden uses. Implement as Flutter widgets under
`frontend/lib/commons/components/`.

Every component reads from `Theme.of(context).extension<NotifTokens>()!`. No
direct token imports.

### 11.1 Eyebrow

**Purpose.** Small tracked-out mono label above a content block. Reads as a
classified-document section stamp. Structural, never decorative.

**Anatomy.**
- Single line of text
- Type role: `eyebrow` (11sp) or `micro` (10.5sp) when even tighter
- Color: `inkMute` default, `inkDim` for emphasis, `accent` when tagging an
  active/current state

**States.** Not interactive. Color is the only variable.

**Use for.** Section kickers above titles, form-group labels, status rows
("LAST POLL 14:32"), identifying the active colorway/scheme in small chrome.

**Don't.** Use as body copy. Use without tracking. Stack two Eyebrows next
to each other — pick one and let it carry the label.

### 11.2 Rule

**Purpose.** Plain 1px horizontal hairline. No prefix, no label.

**Anatomy.**
- 1dp height
- Color: `rule` default, `ruleStrong` when actually separating content
  (rather than just breaking rhythm)

**Use for.** Subsection separation inside a panel, top/bottom of AppBar,
between list items that don't warrant dashed KV rules.

**Don't.** Stack two rules close together. Use dashed style — that's KV's job.

### 11.3 IndexRule

**Purpose.** Hairline rule prefixed with a zero-padded section number and an
Eyebrow-styled title, optionally followed by right-side meta. The numbered
spine of the printed-document feel.

**Anatomy.**
- Left: `01` / `02` / etc. in micro-mono, `inkMute`, zero-padded to 2 digits
- Optional Eyebrow title next to the number, `inkDim`
- Hairline (`rule`) filling remaining space
- Optional right-side micro-mono meta, `inkMute`

**Composition.** `{NN}  {TITLE}  ──────── {RIGHT}`

**Use for.** Primary section dividers in Settings and long-form content.
A page has 3–8 of them stacked like a table of contents.

**Don't.** Use as an item delimiter (too heavy). Use without a number (it
becomes just a titled rule — use Rule instead). Nest IndexRules.

### 11.4 CornerMarks

**Purpose.** Four blueprint-style tick marks inside a card. Signals
"technical drawing / instrument panel" rather than "card." Applied sparingly.

**Anatomy.**
- 8 absolutely-positioned 1px lines: at each corner, one horizontal + one
  vertical stroke
- Length: 10dp; inset: 6dp from each edge
- Color: `ruleStrong`

**Use for.** Hero card on About, the active-status card on Settings, any
card the designer wants to read as "instrument readout" rather than "card."

**Don't.** Apply to every card — defeats the purpose. Animate. Thicken
beyond 1px. Move the inset.

### 11.5 Field

**Purpose.** Form wrapper — label, optional required marker, optional right
meta, child input, optional hint. Separates label from input, consistent
across the form.

**Anatomy.**
- Top row: micro-mono label (`inkDim`) left, optional required marker
  (`*` in `accent`), optional right-side micro-mono meta (`inkMute`)
- Child: an Input, Checkbox, Radio row, etc.
- Optional hint below in micro-mono, `inkMute`, lowercase (the hint is
  prose, not a stamp)
- 6dp vertical gaps between rows

**Use for.** Every labeled form control.

**Don't.** Use as a card wrapper. Put more than one input inside one Field.

### 11.6 Input (underline)

**Purpose.** Text input with a single bottom rule. Manuscript form aesthetic.

**Anatomy.**
- Single bottom 1px rule, `ruleStrong` at rest
- Text in body role, `ink`
- Optional prefix / suffix (micro-mono, `inkMute`)
- 6dp padding below text
- Cursor color: `accent`

**States.**

| State    | Bottom rule                | Text      | Notes                |
| -------- | -------------------------- | --------- | -------------------- |
| Rest     | `ruleStrong`, 1dp          | `ink`     |                      |
| Focus    | `accent`, 2dp              | `ink`     |                      |
| Error    | `feedback.error`, 1dp      | `ink`     | Error hint replaces placeholder hint, same row as Field hint |
| Disabled | `rule`, 1dp                | `inkMute` | No caret             |

**Use for.** All text inputs on non-auth screens. Backend URL, search,
source URLs.

**Don't.** Wrap in `OutlineInputBorder`. Add a background fill. Round
corners. Nest an icon inside the input — use prefix/suffix instead.

### 11.7 Button

Four variants. Rectangular. Uppercase mono labels with 0.15em tracking.
Heights: sm 32dp, md 44dp, lg 52dp.

#### 11.7.1 Primary

High-priority CTA. One per screen maximum.

| State    | Fill                                   | Text       | Border           |
| -------- | -------------------------------------- | ---------- | ---------------- |
| Rest     | `btnBg`                                | `btnInk`   | 1px `btnBg`      |
| Hover    | `ink`                                  | `bg1`      | 1px `ink`        |
| Pressed  | `Color.lerp(btnBg, black, 0.12)`       | `btnInk`   | 1px (same)       |
| Focus    | `btnBg`                                | `btnInk`   | 2px `accent`     |
| Disabled | `ruleStrong`                           | `inkMute`  | none             |
| Loading  | `btnBg` @ 0.5 opacity                  | hidden     | + spinner        |

#### 11.7.2 Ghost (default for secondary actions)

| State    | Fill                         | Text      | Border                |
| -------- | ---------------------------- | --------- | --------------------- |
| Rest     | transparent                  | `ink`     | 1px `ruleStrong`      |
| Hover    | `ink` @ 0.04                 | `ink`     | 1px `ink`             |
| Pressed  | `ink` @ 0.08                 | `ink`     | 1px `ink`             |
| Focus    | transparent                  | `ink`     | 2px `accent`          |
| Disabled | transparent                  | `inkMute` | 1px `rule`            |

#### 11.7.3 Accent (rare, for destructive or exceptional actions)

| State    | Fill             | Text       | Border        |
| -------- | ---------------- | ---------- | ------------- |
| Rest     | `accent`         | `bg1`      | 1px `accent`  |
| Hover    | `ink`            | `bg1`      | 1px `ink`     |
| Pressed  | `accent`-darker  | `bg1`      | 1px `accent`  |
| Focus    | `accent`         | `bg1`      | 2px `accent2` |
| Disabled | `ruleStrong`     | `inkMute`  | none          |

#### 11.7.4 Link

| State    | Fill            | Text         | Border     |
| -------- | --------------- | ------------ | ---------- |
| Rest     | transparent     | `accent`     | none       |
| Hover    | transparent     | `accent` + underline | none |
| Disabled | transparent     | `inkMute`    | none       |

**Don't.** Round corners. Drop shadows. Use emoji/icons as labels without
text. Mix multiple Primary buttons on one screen. Animate the hover
transition longer than `short` (180 ms).

### 11.8 Checkbox

**Anatomy.**
- 14×14 square, 1px `ruleStrong` border, `rNone`
- Unchecked: transparent fill, no glyph
- Checked: `ink` fill, 1.5px `bg1` SVG checkmark
- Optional body-mono label (12sp) to the right, `ink`

**States.**

| State    | Border        | Fill     | Label   |
| -------- | ------------- | -------- | ------- |
| Rest     | `ruleStrong`  | —        | `ink`   |
| Hover    | `ink`         | —        | `ink`   |
| Checked  | `ink`         | `ink`    | `ink`   |
| Disabled | `rule`        | —        | `inkMute` |
| Focus    | 2px `accent`  | —        | `ink`   |

**Don't.** Round corners. Use a different color for the checkmark than `bg1`.

### 11.9 Radio

**Anatomy.** 12dp outer circle, 1px `ruleStrong` border, 4dp inner dot
filled `ink` when selected. Otherwise follows Checkbox's state logic.

Used in the existing `_BackendUrlModeSelector` in Settings; replace that
ad-hoc implementation with the shared Radio.

### 11.10 Switch

Flutter-native need (the experiment doesn't have one). For non-auth screens
use `Switch.adaptive` with:

- `activeThumbColor`: `accent`
- `activeTrackColor`: `accent` @ 0.4
- `inactiveThumbColor`: `inkDim`
- `inactiveTrackColor`: `rule`

### 11.11 Card

**Purpose.** Framed compartment. No elevation, no floating.

**Anatomy.**
- Background: `bg2`
- Optional 1px `rule` border
- Optional `CornerMarks` overlay
- Default padding: 24dp; minimum 16dp
- `rNone` corners

**States.**

| State    | Background    | Border          |
| -------- | ------------- | --------------- |
| Rest     | `bg2`         | 1px `rule`      |
| Tapped   | `bg3`         | 1px `accent2`   |
| Disabled | `bg2`         | 1px `rule`, ink-muted content |

**Don't.** Shadow. Float. Round. Stack three deep — two max.

### 11.12 Tag

**Purpose.** Tight bordered chip for categorical labels (kind badges like
`FORUM` / `RSS` / `GIT` / `MAIL`, hashtags, source types).

**Anatomy.**
- Micro-mono text
- 1px border
- Padding 2×6dp
- `rNone` corners

**Tones.**

| Tone     | Text       | Border     |
| -------- | ---------- | ---------- |
| Default  | `inkDim`   | `rule`     |
| Accent   | `accent`   | `accent`   |
| Muted    | `inkMute`  | `rule`     |

**Don't.** Fill with color. Use as a button. Round. Scale the text above
micro (if you want it bigger, use an Eyebrow).

### 11.13 AppBar

**Purpose.** Thin top bar.

**Anatomy.**
- Left slot: Logotype + `/ {context}` breadcrumb (micro-mono, `inkMute`)
- Center slot (optional): Eyebrow-styled status
- Right slot: icon actions, StatusDot
- Padding 14×20dp mobile, 14×24dp desktop
- 1px `rule` bottom border (not `ruleStrong` — appbar rides light)
- Background: `bg1` or `bg0` depending on scaffold

**Don't.** Elevate. Fill with accent. Use Material's default AppBar theme.

### 11.14 Logotype

**Purpose.** Wordmark. Used in AppBar, auth top rail, splash.

**Anatomy.**
- 16dp outlined square (1px `ink` stroke)
- 8dp `accent` fill inside the square
- 4dp `bg1` inner dot
- Wordmark `notif` in Instrument Serif italic at 1.35 × glyph size, `ink`
- 8dp gap between glyph and wordmark

**Sizes.** 13dp (mobile AppBar), 14dp (desktop AppBar), 16dp (auth rail).

**Don't.** Scale glyph and wordmark independently. Use roman (non-italic).
Place on a high-contrast accent background where the inner fill
disappears.

### 11.15 KV

**Purpose.** Key/value row for metadata and settings readouts. Paper-form
aesthetic via the dashed rule.

**Anatomy.**
- Key: micro-mono, uppercase, `inkMute`, min-width 120dp
- Value: body-mono, `ink`
- Optional right-side micro-mono, `inkMute` (timestamp, unit)
- Bottom border: 1px **dashed**, `rule`

**Use for.** Build info, active configuration, notification metadata, any
key-value block that isn't editable.

**Don't.** Multiple values per row. Solid bottom rule — that stops reading
as "form field." Use for editable settings — those are Field + Input.

### 11.16 StatusDot

**Purpose.** Small colored dot with a pulse ring, optionally labeled.
Indicates live / sync / idle / error states.

**Anatomy.**
- 6dp solid dot, colored per state
- 3dp pulse ring at 20% alpha of dot color (CSS: `box-shadow: 0 0 0 3px`)
- Optional micro-mono label, `inkDim`, spaced 8dp from the dot

**States.**

| State    | Color              | Typical label   |
| -------- | ------------------ | --------------- |
| Live     | `accent`           | "LIVE"          |
| Synced   | `accent2`          | "SYNCED"        |
| Idle     | `inkMute`          | "IDLE"          |
| Warning  | `feedback.warning` | "WARNING"       |
| Error    | `feedback.error`   | "ERROR"         |

**Don't.** Animate heavily — this is calm, not alarmed. Scale beyond 6dp.
Stack multiple per screen (pick one to dominate).

### 11.17 Icon

**Primary set.** Material Sharp (built-in, zero dependency). Angular,
geometric. Usage: `Icons.notifications_sharp`, `Icons.settings_sharp`, etc.

**Custom set.** Minimal 1.25px-stroke line icons for glyphs the experiment
defines (`rss`, `thread`, `moon`, `sun`, `rss`, `menu`, `star`, `filter`,
`archive`, `clock`) where Material Sharp is too generic. Port from the
experiment's `<Icon>` paths.

**Sizes.** 14dp inline, 18dp in buttons, 24dp in AppBar.

**Color.** Inherits context (`inkDim` default, `accent` when active, etc.).

**Don't.** Mix icon sets per component — pick the most specific set that
covers your glyphs. Color icons by `accent` as their default.

### 11.18 Auth-specific components (carry over)

These exist in `frontend/lib/commons/` already and stay there — they're
auth-only and not part of the non-auth component catalog:

- `AuthBackground`, `AuthChrome`, `AuthTextureTuner`, `AuthPalette`
- `DitherOverlay`
- Shared `AppTextField` for login/register (already extracted)
- `login_register_fields.dart`

Once `AuthPalette` derives from the active colorway (§12), these keep
working unchanged.

### 11.19 Components being retired

Replace with catalog primitives:

| Current                         | Replace with                 | Where                 |
| ------------------------------- | ---------------------------- | --------------------- |
| `_SettingsPanel` (private)      | `Card` + `IndexRule` header  | `settings.dart`       |
| `_FramedPanel` (private)        | `Card` (optional `CornerMarks`) | `about.dart`         |
| `_ActionButton` (private)       | `Button` (primary/ghost)     | `about.dart`          |
| `_HeroActionTile` (private)     | `Card` containing `Button`   | `about.dart`          |
| `_BackendUrlModeSelector`       | `Radio` + `Field`            | `settings.dart`       |
| Ad-hoc `OutlineInputBorder`     | `Input` (underline)          | `settings.dart`       |
| Duplicated `_titleStyle` etc.   | shared `notif_text_theme.dart` | both                 |

---

## 12. Auth reconciliation

The user decision: auth buttons and accent hues follow the active colorway,
but the auth gradient, panel fill, and texture pipeline stay fixed. The
signature backdrop is not applied to auth.

Changes to `AuthPalette`:

| Token in `AuthPalette`                      | Behavior                         |
| ------------------------------------------- | -------------------------------- |
| `panel`, `panelBorder`, `panelShadow`       | Fixed (current values)           |
| `baseGradientColors`, `baseGradientStops`   | Fixed                            |
| `bloomColors`, `bloomStops`                 | Fixed                            |
| `transitionColors`, `floorFadeColors`       | Fixed                            |
| `grainFrom`, `grainTo`                      | Fixed                            |
| `panelAlpha`, `glassBlurSigma`, etc.        | Fixed                            |
| `primaryButtonBase`                         | Derive: `colorway.btnBg`         |
| `secondaryButtonBase`                       | Derive: `colorway.btnBg` shaded  |
| `buttonBorder`                              | Derive: `colorway.ruleStrong`    |
| `fabGlass`, `fabShadow`                     | Fixed                            |

Rationale: the gradient and bloom *are* the auth identity — they represent
"pre-brand, pre-login, environment." Button tint is the place the user's
chosen colorway peeks through, foreshadowing the interior.

---

## 13. Patterns

Screen templates, referencing §11 components.

### 13.1 Settings

Layout: sidebar (desktop) or stack (mobile).

- **AppBar** top — Logotype + `/ settings`, close/back icon right.
- **Sidebar** left — desktop only. Sections listed with 2-digit numeric
  prefixes, matching the IndexRule spine of the main pane. Active section
  gets 2dp `accent` left-border and `accent`-tinted fill at low alpha.
- **Main pane** — per section:
  - Eyebrow kicker (`"02 · Appearance"`)
  - Oversized serif title, italic, `heading` or `title` size
  - Body-mono intro, `inkDim`, short
  - Stack of `IndexRule` section headers, each followed by its controls:
    - Picker grids, radios, switches, inputs
  - `lg` spacing between sections

Adopt this structure in `settings.dart`: replace `_SettingsPanel` with
`IndexRule` headers + unframed content (no more double-framing).

### 13.2 About

Current structure is close. Changes:

- Promote hero card to use `CornerMarks`.
- Replace `_FramedPanel` with `Card`.
- Replace `_ActionButton` / `_HeroActionTile` with `Button`.
- Keep the four-panel 2×2 grid on wide viewports, column stack on narrow.

### 13.3 Feed (new)

Mirrors the experiment's `FeedTeaser`. Designed around grouped digests.

- **AppBar** — Logotype + `/ feed`, filter/search/settings icons right.
- **Sticky time-group header** — Eyebrow-accent time string ("TODAY · 14:30
  digest"), right-aligned item count. `bg0` with light backdrop-blur.
- **Source row** — 3-char `KIND` Tag (`FORUM`/`RSS`/`GIT`/`MAIL`) +
  serif-italic source name + hairline rule filling remaining space.
- **Item row** — 6dp dot (`accent` if hot, else `inkFaint`), serif-long title,
  micro-mono meta, right-aligned age. Dashed `rule` bottom border. Cursor
  pointer; item navigation on tap.
- **Footer** — 1px `rule` top, next-poll Eyebrow left, StatusDot right.

### 13.4 Empty state

From experiment's `EmptyState`.

- **AppBar** same as Feed.
- **Centered stack**:
  - `DitherOrb` (32dp on mobile, 220dp on desktop), faded to ~85% opacity
  - `Eyebrow` accent: "All clear"
  - Serif title italic: "No new signal."
  - Body-dim prose with small `accent` inline highlights for the watched
    source count and next poll time
  - Two buttons: ghost "Manage sources", primary "Add a source"
- **Quiet footer** — last-poll / next-poll Eyebrows, StatusDot "IDLE".

### 13.5 Dialog

- Surface: `bg3`
- Border: 1px `rule`
- Corners: `rSm` (4dp) — the one place non-auth softens
- Padding: 24dp
- No shadow, no backdrop blur
- Close action: ghost Button top-right; confirm: primary Button bottom-right

### 13.6 Error state

- Error-filled StatusDot at top
- Serif heading: what broke
- Body-mono: what to try
- Ghost Button: retry

---

## 14. Feedback colors

Fixed, shared across all colorways.

| Token              | Value              | Use                                       |
| ------------------ | ------------------ | ----------------------------------------- |
| `feedback.error`   | `#B04040`          | Muted red. Warning stamp, not LED.        |
| `feedback.success` | `#5A8A5E`          | Desaturated sage green.                   |
| `feedback.warning` | `#B09040`          | Dusty amber.                              |

On light-scheme colorways, verify 4.5:1 contrast against `bg1` and `bg2`.
Deepen to `#8A2020` / `#3A6A40` / `#8A6A20` if any pair fails.

---

## 15. Implementation order

Each step ships on its own. Don't batch.

1. **Token ThemeExtension.** `NotifColorway` + `NotifTokens extends
   ThemeExtension<NotifTokens>`. One colorway implemented (Dusk 1). Theme
   passes extension into `MaterialApp`. No visual change yet.
2. **Migrate Settings + About to read from the extension.** Remove all
   direct `NotifDesignTokens.*` static references in those screens. No
   visual change.
3. **Extract shared text styles.** `notif_text_theme.dart` carries the
   Current set. Remove duplicate `_displayStyle`/`_titleStyle`/etc. from
   `settings.dart` and `about.dart`. Fix the 20/26 drift by picking 22.
4. **Migrate all font usages to `TextTheme`.** Every `fontFamily: ...`
   string in the app body moves to a `TextStyle` derived from
   `Theme.of(context).textTheme.xxx`. Prerequisite for the font switcher.
5. **Add Dusk 2, Midnight, Sage, Daybreak colorways.** Each lists all
   tokens from §3.1. Colorway picker appears in Settings; persists via
   SharedPreferences; theme rebuilds on change.
6. **Scheme toggle.** Settings gets a dark/light switch that only enables
   when the active colorway supports the opposite scheme. For this release,
   Dusk 1/2/Midnight are dark-only; Sage, Daybreak are light-only.
7. **Register new fonts.** Add Newsreader, JetBrains Mono, Inter Tight to
   `pubspec.yaml`. Build Experiment and Hybrid `TextTheme` factories.
8. **Font-set picker in Settings.** Radio: Current / Experiment / Hybrid.
   Theme rebuilds on change.
9. **AuthPalette reconciliation.** Button + bloom-adjacent values derive
   from active colorway per §12. Everything else stays fixed.
10. **Debug tuner additions.** Texture-intensity slider, per-layer toggles,
    signature-backdrop on/off (§10.1).
11. **Component primitives (batch A: static).** `Eyebrow`, `Rule`,
    `IndexRule`, `CornerMarks`, `Logotype`, `KV`, `StatusDot`, `Tag`,
    `AppBar`.
12. **Component primitives (batch B: interactive).** `Field`, `Input`
    (underline), `Button` (4 variants), `Checkbox`, `Radio`, `Switch`,
    `Card`, `Icon`.
13. **SignatureBackdrop widget.** Three layers via `CustomPaint` +
    baked noise image. Intensity reads the debug dial.
14. **Settings refactor.** Replace `_SettingsPanel` with
    `IndexRule` + content. Replace `_BackendUrlModeSelector` with
    `Field` + `Radio`. Replace ad-hoc `OutlineInputBorder` with `Input`.
15. **About refactor.** Replace `_FramedPanel` with `Card`,
    `_ActionButton` with `Button`. Add `CornerMarks` to the hero card.
16. **Home redesign (Feed pattern).** Build `screens/feed.dart` using
    §13.3. Remove the placeholder `NotificationsView`.
17. **Empty state screen.** Route for the first-login / no-sources case.
18. **Promote `style-guide.md`.** Rewrite the guide into the reference
    structure below. Delete sections from this file as they land.

Once 18 lands, `style-guide-todo.md` is empty and gets removed.

### 15.1 Target `style-guide.md` structure

1. Principles — §1 of this doc
2. Foundations — §§7, 8
3. Tokens — §3, full per-colorway tables from §4
4. Typography — §6
5. Texture — §§9, 10 (the dial part scoped to "debug-only")
6. Component catalog — §11 with code examples per primitive
7. Patterns — §13
8. Screens — exemplar screenshots (or ascii mockups) per major route
9. Appendix — parked colorways (§5), feedback colors (§14), implementation
   notes

---

## 16. Open questions

- **Dusk 1 accent2 color.** `#E8A77A` is the current pick (warm sand). Verify
  it reads on `bg1`/`bg2` at body size and doesn't steal attention from
  accent. Alternative: Dusk 2's `#FFD166` — same family, might be too loud.
- **Daybreak name.** Placeholder. Decide once a real Daybreak-themed screen
  is rendered. Alternates: Harbor, Tideline, Mariner, Shoreline, Foreshore.
- **Hybrid `bodyLong`.** Instrument Serif italic is the working choice; if
  long reads feel uncomfortable, fall back to Skyling.
- **Default font set.** Current → shipped; Experiment → once Feed/Empty
  land. The switch-over is a cosmetic decision, not a technical one.
- **Scheme cross-toggle.** Short term: each colorway declares its scheme;
  opposite greys out. Long term: every colorway supports both by generating
  the missing scheme algorithmically (swap `bg*` with `ink*`, shift
  halo/accent hues). Worth doing once 2 light + 3 dark feels confining.
- **Texture default.** `4 / 10` is a guess. Tune after the SignatureBackdrop
  widget exists and can be compared across colorways.
- **Feedback color tuning.** `#B04040` / `#5A8A5E` / `#B09040` were chosen
  for dark mode. Verify contrast on every light colorway (Sage, Daybreak,
  Library light, Dusk light). Expect to darken each.
- **Icon set ownership.** Material Sharp covers most of what the current
  app needs. The experiment's custom set covers things Material doesn't do
  cleanly (thread, rss feed-style, dither-style dot). Pick a stopping point:
  either port all custom icons now or wait until a specific need arises.
- **Auth backdrop in-system.** The decision was "don't apply signature
  backdrop to auth." Revisit if the current auth pipeline turns out to be
  a maintenance burden — SignatureBackdrop could replace it at a lower
  cost, with auth-specific tuning (higher intensity, different halo ramp).
