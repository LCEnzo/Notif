// tokens.jsx — Colorway + token system for Notif
// Four colorways, each with dark (default) and where appropriate light variants.
// Tokens are plain JS objects consumed via <ThemeProvider> pattern (context).

// ─────────────────────────────────────────────────────────────
// Core palette per colorway
// Every colorway defines the full token set for its Dark state.
// Some colorways also define a Light state.
// ─────────────────────────────────────────────────────────────

const COLORWAYS = {
  // ═══ PURPLE DUSK ═══ (refinement of current)
  dusk: {
    name: 'Purple Dusk',
    code: '01',
    description: 'Original. Phosphor sunset, dithered fade.',
    light: {
      bg0: '#ede6ef',
      bg1: '#e0d4e2',
      bg2: '#d1c0d4',
      bg3: '#c1a8c6',
      halo1: '#c94da1',
      halo2: '#8a4dc9',
      halo3: '#6a3c9a',
      ink: '#2a0c2e',
      inkDim: '#4a2650',
      inkMute: '#6b4a72',
      inkFaint: 'rgba(42,12,46,0.4)',
      accent: '#8a2075',
      accent2: '#c96a1a',
      rule: 'rgba(42,12,46,0.22)',
      ruleStrong: 'rgba(42,12,46,0.5)',
      btnBg: '#2a0c2e',
      btnInk: '#ede6ef',
      btnBgAlt: 'transparent',
      btnInkAlt: '#2a0c2e',
      halftone: '#2a0c2e',
      halftoneBlend: 'multiply',
      grainOpacity: 0.20,
      scheme: 'light',
    },
    dark: {
      // backdrop
      bg0: '#0a0310',           // deep void
      bg1: '#1a0a26',           // mid purple
      bg2: '#2d1244',           // card base
      bg3: '#3a1a55',           // raised
      // halo (for grain top)
      halo1: '#ff2bb3',         // hot magenta core
      halo2: '#b820cc',
      halo3: '#4c1d95',
      // text
      ink: '#f5e6ff',           // cream-violet
      inkDim: '#c9b0e0',
      inkMute: '#8a7099',
      inkFaint: 'rgba(245,230,255,0.35)',
      // accents
      accent: '#ffb3e6',        // pink accent
      accent2: '#ffd166',       // warm pop
      rule: 'rgba(245,230,255,0.18)',
      ruleStrong: 'rgba(245,230,255,0.35)',
      // interactive
      btnBg: '#f5e6ff',
      btnInk: '#1a0a26',
      btnBgAlt: 'transparent',
      btnInkAlt: '#f5e6ff',
      // halftone color (floor dots)
      halftone: '#000',
      halftoneBlend: 'multiply',
      grainOpacity: 0.28,
      scheme: 'dark',
    },
  },

  // ═══ SAGE OLIVE ═══ (Urbit)
  sage: {
    name: 'Sage',
    code: '02',
    description: 'Paper & cactus. Urbit field journal.',
    dark: {
      bg0: '#0e0f0a',
      bg1: '#1a1c14',
      bg2: '#22261b',
      bg3: '#2d3325',
      halo1: '#c9cc8d',
      halo2: '#8a9560',
      halo3: '#3a4528',
      ink: '#e8e4cc',
      inkDim: '#b8b494',
      inkMute: '#7d7a5f',
      inkFaint: 'rgba(232,228,204,0.32)',
      accent: '#d4a05a',
      accent2: '#a8b070',
      rule: 'rgba(232,228,204,0.18)',
      ruleStrong: 'rgba(232,228,204,0.35)',
      btnBg: '#e8e4cc',
      btnInk: '#1a1c14',
      btnBgAlt: 'transparent',
      btnInkAlt: '#e8e4cc',
      halftone: '#000',
      halftoneBlend: 'multiply',
      grainOpacity: 0.32,
      scheme: 'dark',
    },
    light: {
      bg0: '#e8e2c8',           // aged paper
      bg1: '#ded7b8',
      bg2: '#d2caa6',
      bg3: '#c5bc96',
      halo1: '#8a9560',
      halo2: '#a8b070',
      halo3: '#c9cc8d',
      ink: '#1a1c14',
      inkDim: '#3a3d2a',
      inkMute: '#5d5e42',
      inkFaint: 'rgba(26,28,20,0.4)',
      accent: '#8a5a2a',
      accent2: '#556832',
      rule: 'rgba(26,28,20,0.22)',
      ruleStrong: 'rgba(26,28,20,0.5)',
      btnBg: '#1a1c14',
      btnInk: '#e8e2c8',
      btnBgAlt: 'transparent',
      btnInkAlt: '#1a1c14',
      halftone: '#1a1c14',
      halftoneBlend: 'multiply',
      grainOpacity: 0.22,
      scheme: 'light',
    },
  },

  // ═══ LIBRARY TEAL ═══ (your beautiful description)
  library: {
    name: 'Library',
    code: '03',
    description: 'Library binding rendered as dark mode.',
    dark: {
      bg0: '#071914',           // darker than ground
      bg1: '#0c2823',           // ground
      bg2: '#133a32',           // card
      bg3: '#1f4a42',           // raised / mid-teals
      halo1: '#4a8a7a',
      halo2: '#2a5a50',
      halo3: '#0c2823',
      ink: '#e6dcc5',           // cream body
      inkDim: '#b8ae97',
      inkMute: '#7a8882',
      inkFaint: 'rgba(230,220,197,0.32)',
      accent: '#d4b07a',        // warm counterweight
      accent2: '#8aa59a',
      rule: 'rgba(230,220,197,0.16)',
      ruleStrong: 'rgba(230,220,197,0.32)',
      btnBg: '#e6dcc5',
      btnInk: '#0c2823',
      btnBgAlt: 'transparent',
      btnInkAlt: '#e6dcc5',
      halftone: '#000',
      halftoneBlend: 'multiply',
      grainOpacity: 0.30,
      scheme: 'dark',
    },
    light: {
      bg0: '#f0e8cf',           // warm cream paper
      bg1: '#e6dcc5',
      bg2: '#dccf9f',
      bg3: '#c9ba82',
      halo1: '#1f4a42',
      halo2: '#4a8a7a',
      halo3: '#8aa59a',
      ink: '#0c2823',
      inkDim: '#2a5046',
      inkMute: '#5d6e68',
      inkFaint: 'rgba(12,40,35,0.4)',
      accent: '#8a5a2a',
      accent2: '#1f4a42',
      rule: 'rgba(12,40,35,0.22)',
      ruleStrong: 'rgba(12,40,35,0.5)',
      btnBg: '#0c2823',
      btnInk: '#e6dcc5',
      btnBgAlt: 'transparent',
      btnInkAlt: '#0c2823',
      halftone: '#0c2823',
      halftoneBlend: 'multiply',
      grainOpacity: 0.20,
      scheme: 'light',
    },
  },

  // ═══ MIDNIGHT CYAN ═══
  cyan: {
    name: 'Midnight',
    code: '04',
    description: 'Radio static in the ocean trench.',
    light: {
      bg0: '#e4eef2',
      bg1: '#d5e3ea',
      bg2: '#c2d5df',
      bg3: '#a8c0cd',
      halo1: '#0891b2',
      halo2: '#0e5a7a',
      halo3: '#164e63',
      ink: '#071624',
      inkDim: '#1e3a4d',
      inkMute: '#4a6270',
      inkFaint: 'rgba(7,22,36,0.4)',
      accent: '#a3550a',
      accent2: '#0891b2',
      rule: 'rgba(7,22,36,0.22)',
      ruleStrong: 'rgba(7,22,36,0.5)',
      btnBg: '#071624',
      btnInk: '#e4eef2',
      btnBgAlt: 'transparent',
      btnInkAlt: '#071624',
      halftone: '#071624',
      halftoneBlend: 'multiply',
      grainOpacity: 0.20,
      scheme: 'light',
    },
    dark: {
      bg0: '#030a12',
      bg1: '#081624',
      bg2: '#0f2438',
      bg3: '#1a3350',
      halo1: '#22d3ee',
      halo2: '#0891b2',
      halo3: '#164e63',
      ink: '#d6eef8',
      inkDim: '#8fb6c5',
      inkMute: '#5d7a87',
      inkFaint: 'rgba(214,238,248,0.30)',
      accent: '#fbbf24',       // amber signal
      accent2: '#67e8f9',
      rule: 'rgba(214,238,248,0.16)',
      ruleStrong: 'rgba(214,238,248,0.32)',
      btnBg: '#d6eef8',
      btnInk: '#081624',
      btnBgAlt: 'transparent',
      btnInkAlt: '#d6eef8',
      halftone: '#000',
      halftoneBlend: 'multiply',
      grainOpacity: 0.30,
      scheme: 'dark',
    },
  },
};

// ─────────────────────────────────────────────────────────────
// Type scale — shared across all colorways
// ─────────────────────────────────────────────────────────────
const TYPE = {
  serif: "'Instrument Serif', 'Times New Roman', Georgia, serif",
  serifLong: "'Newsreader', Georgia, serif",
  mono: "'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace",
  sans: "'Inter Tight', system-ui, sans-serif",
  scale: {
    display: { size: 64, lh: 0.95, tracking: -0.02, family: 'serif' },
    title: { size: 40, lh: 1.02, tracking: -0.015, family: 'serif' },
    heading: { size: 22, lh: 1.15, tracking: -0.01, family: 'serif' },
    eyebrow: { size: 11, lh: 1.0, tracking: 0.2, family: 'mono', upper: true },
    body: { size: 13, lh: 1.5, tracking: 0, family: 'mono' },
    bodyLong: { size: 15, lh: 1.55, tracking: 0, family: 'serifLong' },
    micro: { size: 10.5, lh: 1.3, tracking: 0.12, family: 'mono', upper: true },
    code: { size: 12, lh: 1.5, tracking: 0, family: 'mono' },
  },
};

// ─────────────────────────────────────────────────────────────
// Theme context + hook
// ─────────────────────────────────────────────────────────────
const ThemeCtx = React.createContext(null);

function ThemeProvider({ colorway = 'dusk', scheme = 'dark', texture = 10, children }) {
  const cw = COLORWAYS[colorway];
  const t = cw[scheme] || cw.dark;
  const value = React.useMemo(
    () => ({ t, type: TYPE, colorway, scheme, cwMeta: cw, texture }),
    [colorway, scheme, texture, cw, t]
  );
  return <ThemeCtx.Provider value={value}>{children}</ThemeCtx.Provider>;
}

function useTheme() {
  const v = React.useContext(ThemeCtx);
  if (!v) throw new Error('useTheme must be used inside ThemeProvider');
  return v;
}

// Pick right text style from scale
function typeStyle(key, { type } = { type: TYPE }) {
  const s = type.scale[key];
  return {
    fontFamily: type[s.family],
    fontSize: s.size,
    lineHeight: s.lh,
    letterSpacing: (s.tracking || 0) + 'em',
    textTransform: s.upper ? 'uppercase' : 'none',
  };
}

Object.assign(window, { COLORWAYS, TYPE, ThemeProvider, ThemeCtx, useTheme, typeStyle });
