# Notif UI Style Guide

## Visual Direction
- Dark utility first, with luminous violet accents and frosted glass surfaces.
- The interface should feel precise, technical, and a little neon rather than playful or soft.
- Use sharp contrast and restrained translucency instead of heavy decoration.

## Core Palette
| Token | Value | Use |
| --- | --- | --- |
| App primary | `#451AAC` | App bars, seed color, primary actions outside auth |
| Primary container | `#5935AD` | Secondary purple surfaces in the app theme |
| Tertiary accent | `#4C12D3` | Accent emphasis when a brighter violet is needed |
| Glass base | `#E3E3E7` at 20% opacity | Auth card, tuner, and glass help button fills |
| Glass border | `#29FFFFFF` | Glass outlines and subtle edge definition |
| Glass shadow | `#38000000` | Large, soft shadows under glass surfaces |
| Primary auth button | `#D14B22B5` | Log in / main confirmation action |
| Secondary auth button | `#D16339C2` | Register / back / secondary auth action |
| Button border | `#4DFFFFFF` | Shared auth button outline |
| Grain ramp | `#16040B` to `#9A41DB` | Auth texture color interpolation |
| Background gradient | `#7716A4`, `#5D148F`, `#33104F`, `#0B0716`, `#000000` | Main auth background depth |

## Typography
- Primary app font: `Hack Regular`.
- Large branded headings can stay bold and high contrast, but avoid overly rounded or playful type treatments.
- On glass surfaces, use white for primary text, `Colors.white70` for secondary text, and `Colors.white54` for hints.
- Auth buttons use semibold labels for clarity without feeling heavy.

## Shape And Spacing
- Shared auth radius: `6dp`.
- Apply that same `6dp` radius to the auth card, tuner, About button, and auth buttons.
- Standard auth vertical rhythm: `16dp` between fields and actions.
- Auth card padding: `28dp`.
- Screen edge padding around auth content: `32dp`.
- General content padding on standard screens: `16dp` to `24dp`.

## Glass Surface Recipe
Use this for auth surfaces that should feel related:
- Radius: `6dp`
- Fill: `AuthPalette.panel` at `0.2` alpha
- Border: `AuthPalette.panelBorder`
- Blur: `18dp`
- Shadow: `AuthPalette.panelShadow` with `28dp` blur and `16dp` Y offset

## Auth Component Rules
### Auth card
- Use the shared glass recipe.
- Keep text and icons light so the panel reads as the same object as the tuner.
- Inputs should use white text, white-70 labels/icons, white-54 hints, and soft white underline borders.

### Auth buttons
- Use the same `6dp` radius as the card.
- Keep white text on purple fills.
- Prefer the darker violet for the main action and the lighter violet for the secondary action.
- Use the shared translucent white border so buttons still feel part of the same glass-heavy system.

### About button and tuner
- Treat both as extensions of the auth card system rather than separate widgets.
- Reuse the same radius, border, blur, and shadow values as the auth card.

## Non-Auth Screens
- App bars should continue to use `Theme.of(context).colorScheme.primary`.
- Content pages can stay flatter and more standard than auth, but should still respect the same purple family and typography.
- If a non-auth surface adopts the glass look later, reuse the auth glass recipe instead of inventing a second translucent style.

## Implementation References
- `frontend/lib/main.dart`
- `frontend/lib/commons/auth_palette.dart`
- `frontend/lib/commons/auth_chrome.dart`
- `frontend/lib/commons/login_register_fields.dart`
- `frontend/lib/commons/auth_texture_tuner.dart`
