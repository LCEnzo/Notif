// textures.jsx — Grain, halftone, dither — the signature texture system.
// Pure SVG/CSS, no image assets.

// ═══ Turbulence grain overlay ═══
// Applied absolutely-positioned over any surface. Uses SVG feTurbulence.
function Grain({ opacity, blend = 'overlay', contrast = 140, scale = 0.85 }) {
  const { t, texture } = useTheme();
  const opa = opacity != null ? opacity : (t.grainOpacity * (texture / 10));
  const id = React.useId();
  return (
    <svg
      aria-hidden
      style={{
        position: 'absolute', inset: 0, width: '100%', height: '100%',
        pointerEvents: 'none', mixBlendMode: blend, opacity: opa,
        zIndex: 0,
      }}
    >
      <filter id={id}>
        <feTurbulence type="fractalNoise" baseFrequency={scale} numOctaves="2" stitchTiles="stitch" seed="7" />
        <feColorMatrix values={`0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 ${contrast / 100} 0`} />
      </filter>
      <rect width="100%" height="100%" filter={`url(#${id})`} />
    </svg>
  );
}

// ═══ Halftone floor (your curved dot pattern) ═══
// A radial-mask gradient of dots that gets denser toward the bottom, with a curved top edge.
function HalftoneFloor({ height = 320, curve = 60, opacity = 1 }) {
  const { t, texture } = useTheme();
  const id = React.useId();
  const opa = opacity * (texture / 10);
  return (
    <svg
      aria-hidden
      width="100%" height={height}
      preserveAspectRatio="none"
      style={{
        position: 'absolute', bottom: 0, left: 0, right: 0,
        pointerEvents: 'none', opacity: opa,
        mixBlendMode: t.halftoneBlend,
        zIndex: 1,
      }}
    >
      <defs>
        <pattern id={`dots-${id}`} x="0" y="0" width="6" height="6" patternUnits="userSpaceOnUse">
          <circle cx="3" cy="3" r="1.3" fill={t.halftone} />
        </pattern>
        <linearGradient id={`fade-${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="black" stopOpacity="0" />
          <stop offset="40%" stopColor="black" stopOpacity="0.4" />
          <stop offset="100%" stopColor="black" stopOpacity="1" />
        </linearGradient>
        <mask id={`mask-${id}`}>
          <rect width="100%" height="100%" fill={`url(#fade-${id})`} />
        </mask>
        <clipPath id={`curve-${id}`}>
          <path d={`M 0 ${curve} Q 50 0, 100 ${curve} L 100 ${height} L 0 ${height} Z`}
            transform={`scale(10, 1)`} />
        </clipPath>
      </defs>
      <g mask={`url(#mask-${id})`}>
        <rect width="100%" height={height} fill={`url(#dots-${id})`} />
      </g>
    </svg>
  );
}

// Curved halftone — with arched top edge using pattern of increasing dot size
function CurvedHalftone({ height = 260, intensity = 1 }) {
  const { t, texture } = useTheme();
  const opa = intensity * (texture / 10);
  const id = React.useId();
  // Build rows of dots w/ increasing radius
  const rows = [];
  const rowCount = 28;
  for (let r = 0; r < rowCount; r++) {
    const y = (r / rowCount) * height;
    const prog = r / (rowCount - 1);
    const dotR = 0.4 + prog * 2.2;
    const spacing = 8;
    const cols = Math.ceil(1200 / spacing) + 2;
    const rowDots = [];
    for (let c = 0; c < cols; c++) {
      const x = c * spacing + (r % 2 ? spacing / 2 : 0);
      // Curve mask: dots appear only below a cosine curve
      const centerX = 600;
      const curveY = Math.cos((x - centerX) / 800) * 30 + 12;
      if (y < curveY) continue;
      rowDots.push(<circle key={c} cx={x} cy={y} r={dotR} fill={t.halftone} />);
    }
    rows.push(<g key={r}>{rowDots}</g>);
  }
  return (
    <svg
      aria-hidden
      viewBox={`0 0 1200 ${height}`}
      preserveAspectRatio="xMidYMax slice"
      width="100%" height={height}
      style={{
        position: 'absolute', bottom: 0, left: 0, right: 0,
        pointerEvents: 'none', opacity: opa,
        mixBlendMode: t.halftoneBlend,
      }}
    >
      {rows}
    </svg>
  );
}

// ═══ Backdrop — full-bleed grain + halo + halftone floor ═══
// Signature background for the auth/entry experience.
function SignatureBackdrop({ haloHeight = '55%', floorHeight = 260, children }) {
  const { t, texture } = useTheme();
  return (
    <div style={{
      position: 'absolute', inset: 0, overflow: 'hidden',
      background: t.bg0,
    }}>
      {/* Base vertical gradient: halo → mid → void */}
      <div style={{
        position: 'absolute', inset: 0,
        background: `
          radial-gradient(
            ellipse 60% ${haloHeight} at 50% 0%,
            ${t.halo1} 0%,
            ${t.halo2} 30%,
            ${t.halo3} 55%,
            ${t.bg1} 78%,
            ${t.bg0} 100%
          )
        `,
      }} />
      {/* Grain over whole thing */}
      <Grain opacity={0.35 * (texture / 10)} blend="overlay" scale={0.9} />
      <Grain opacity={0.18 * (texture / 10)} blend="multiply" scale={2.5} contrast={180} />
      {/* Curved halftone floor */}
      <CurvedHalftone height={floorHeight} intensity={1} />
      {children}
    </div>
  );
}

// ═══ Dither shape — ordered-bloom dithered blob for accent imagery ═══
// Pure SVG, deterministic per seed.
function DitherOrb({ size = 240, seed = 1, intensity = 1 }) {
  const { t } = useTheme();
  // Build a bayer-ish pattern of dots whose density follows a radial falloff
  const cells = [];
  const step = 4;
  const cx = size / 2, cy = size / 2;
  // Simple deterministic noise
  const rand = (x, y) => {
    const s = Math.sin(x * 12.9898 + y * 78.233 + seed * 43.1) * 43758.5453;
    return s - Math.floor(s);
  };
  for (let y = 0; y < size; y += step) {
    for (let x = 0; x < size; x += step) {
      const dx = (x - cx) / (size / 2);
      const dy = (y - cy) / (size / 2);
      const d = Math.sqrt(dx * dx + dy * dy);
      // Density = how full near center
      const density = Math.max(0, 1 - d) * intensity;
      if (rand(x, y) < density) {
        const r = 0.8 + rand(x + 1, y) * 1.2;
        cells.push(<circle key={`${x}-${y}`} cx={x} cy={y} r={r} fill={t.ink} opacity={0.85} />);
      }
    }
  }
  return (
    <svg viewBox={`0 0 ${size} ${size}`} width={size} height={size}>
      {cells}
    </svg>
  );
}

// ═══ Dithered landscape (Urbit-style generative) ═══
function DitherLandscape({ width = 600, height = 300, seed = 3 }) {
  const { t } = useTheme();
  const cells = [];
  const step = 3;
  const rand = (x, y) => {
    const s = Math.sin(x * 12.9898 + y * 78.233 + seed * 31.7) * 43758.5453;
    return s - Math.floor(s);
  };
  // multi-octave noise
  const noise = (x, y) => {
    let v = 0;
    v += rand(Math.floor(x / 40), Math.floor(y / 40)) * 0.5;
    v += rand(Math.floor(x / 15), Math.floor(y / 15)) * 0.3;
    v += rand(Math.floor(x / 6), Math.floor(y / 6)) * 0.2;
    return v;
  };
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const n = noise(x, y);
      // Horizontal banding: density peaks around middle-lower
      const vert = 1 - Math.abs((y - height * 0.55) / (height * 0.6));
      const density = n * Math.max(0, vert);
      if (rand(x + 0.1, y + 0.1) < density * 0.9) {
        cells.push(<rect key={`${x}-${y}`} x={x} y={y} width={step - 0.5} height={step - 0.5} fill={t.ink} opacity={0.75} />);
      }
    }
  }
  return (
    <svg viewBox={`0 0 ${width} ${height}`} width="100%" height="100%" preserveAspectRatio="xMidYMid slice">
      {cells}
    </svg>
  );
}

Object.assign(window, {
  Grain, HalftoneFloor, CurvedHalftone, SignatureBackdrop, DitherOrb, DitherLandscape,
});
