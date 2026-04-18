// components.jsx — Notif's shared UI components
// All visually tied to current theme via useTheme().
// Corners are 0 (sharp) — no rounded plastic. Rules & type do the work.

// ───── Eyebrow / kicker label ─────
function Eyebrow({ children, color, style = {} }) {
  const { t } = useTheme();
  return (
    <div style={{
      ...typeStyle('eyebrow', { type: TYPE }),
      color: color || t.inkMute,
      ...style,
    }}>{children}</div>
  );
}

// ───── Section rule ─────
function Rule({ style = {}, strong = false }) {
  const { t } = useTheme();
  return (
    <div style={{
      height: 1,
      background: strong ? t.ruleStrong : t.rule,
      width: '100%',
      ...style,
    }} />
  );
}

// ───── Labeled field (like form fieldset) with code-style meta ─────
function Field({ label, hint, required, children, meta }) {
  const { t } = useTheme();
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkDim }}>
          {label}{required && <span style={{ color: t.accent, marginLeft: 4 }}>*</span>}
        </div>
        {meta && <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>{meta}</div>}
      </div>
      {children}
      {hint && (
        <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, textTransform: 'none', letterSpacing: 0 }}>
          {hint}
        </div>
      )}
    </div>
  );
}

// ───── Text input (bottom-rule underline style) ─────
function Input({ value = '', placeholder = '', type = 'text', prefix, suffix, onChange, style = {} }) {
  const { t } = useTheme();
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      borderBottom: `1px solid ${t.ruleStrong}`,
      paddingBottom: 6,
      ...style,
    }}>
      {prefix && <span style={{ ...typeStyle('body', { type: TYPE }), color: t.inkMute }}>{prefix}</span>}
      <input
        type={type}
        value={value}
        placeholder={placeholder}
        onChange={onChange || (() => {})}
        readOnly={!onChange}
        style={{
          flex: 1, background: 'transparent', border: 'none', outline: 'none',
          color: t.ink,
          ...typeStyle('body', { type: TYPE }),
          fontSize: 15,
          padding: 0,
          caretColor: t.accent,
        }}
      />
      {suffix && <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>{suffix}</span>}
    </div>
  );
}

// ───── Button (primary / ghost / outline) ─────
function Button({ children, variant = 'primary', onClick, style = {}, prefix, suffix, block = false, size = 'md' }) {
  const { t } = useTheme();
  const [hover, setHover] = React.useState(false);

  const pad = size === 'sm' ? '8px 14px' : size === 'lg' ? '16px 22px' : '12px 18px';
  const fontSize = size === 'sm' ? 11 : size === 'lg' ? 13 : 12;

  const variants = {
    primary: {
      background: hover ? t.ink : t.btnBg,
      color: hover ? t.bg1 : t.btnInk,
      border: `1px solid ${t.btnBg}`,
    },
    ghost: {
      background: 'transparent',
      color: t.ink,
      border: `1px solid ${t.ruleStrong}`,
      ...(hover ? { background: 'rgba(255,255,255,0.04)', borderColor: t.ink } : {}),
    },
    link: {
      background: 'transparent',
      color: t.accent,
      border: '1px solid transparent',
      textDecoration: hover ? 'underline' : 'none',
    },
    accent: {
      background: hover ? t.ink : t.accent,
      color: t.bg1,
      border: `1px solid ${t.accent}`,
    },
  };

  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        ...variants[variant],
        padding: pad,
        fontFamily: TYPE.mono,
        fontSize,
        letterSpacing: '0.15em',
        textTransform: 'uppercase',
        cursor: 'pointer',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        width: block ? '100%' : 'auto',
        transition: 'background 0.15s, color 0.15s, border-color 0.15s',
        borderRadius: 0,
        ...style,
      }}
    >
      {prefix}
      {children}
      {suffix}
    </button>
  );
}

// ───── Checkbox (square, no rounding) ─────
function Checkbox({ checked = false, onChange, label }) {
  const { t } = useTheme();
  return (
    <label style={{
      display: 'inline-flex', alignItems: 'center', gap: 10,
      cursor: 'pointer', userSelect: 'none',
    }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        width: 14, height: 14,
        border: `1px solid ${t.ruleStrong}`,
        background: checked ? t.ink : 'transparent',
      }}>
        {checked && (
          <svg width="10" height="10" viewBox="0 0 10 10">
            <path d="M2 5 L4 7 L8 3" stroke={t.bg1} strokeWidth="1.5" fill="none" />
          </svg>
        )}
      </span>
      {label && (
        <span style={{ ...typeStyle('body', { type: TYPE }), color: t.ink, fontSize: 12 }}>{label}</span>
      )}
    </label>
  );
}

// ───── Card (container with optional corner marks) ─────
function Card({ children, style = {}, bordered = true, corners = false, bleed = 0, pad = 24 }) {
  const { t } = useTheme();
  return (
    <div style={{
      position: 'relative',
      background: t.bg2,
      border: bordered ? `1px solid ${t.rule}` : 'none',
      padding: pad,
      ...style,
    }}>
      {corners && <CornerMarks />}
      {children}
    </div>
  );
}

// ───── Corner marks (tick marks in each corner, blueprint-style) ─────
function CornerMarks({ inset = 6, size = 10, color }) {
  const { t } = useTheme();
  const c = color || t.ruleStrong;
  const line = { position: 'absolute', background: c };
  return (
    <>
      {/* TL */}
      <div style={{ ...line, top: inset, left: inset, width: size, height: 1 }} />
      <div style={{ ...line, top: inset, left: inset, width: 1, height: size }} />
      {/* TR */}
      <div style={{ ...line, top: inset, right: inset, width: size, height: 1 }} />
      <div style={{ ...line, top: inset, right: inset, width: 1, height: size }} />
      {/* BL */}
      <div style={{ ...line, bottom: inset, left: inset, width: size, height: 1 }} />
      <div style={{ ...line, bottom: inset, left: inset, width: 1, height: size }} />
      {/* BR */}
      <div style={{ ...line, bottom: inset, right: inset, width: size, height: 1 }} />
      <div style={{ ...line, bottom: inset, right: inset, width: 1, height: size }} />
    </>
  );
}

// ───── Tag / chip (mono, thin) ─────
function Tag({ children, tone = 'default', style = {} }) {
  const { t } = useTheme();
  const tones = {
    default: { color: t.inkDim, border: t.rule },
    accent: { color: t.accent, border: t.accent },
    muted: { color: t.inkMute, border: t.rule },
  };
  const v = tones[tone] || tones.default;
  return (
    <span style={{
      ...typeStyle('micro', { type: TYPE }),
      border: `1px solid ${v.border}`,
      color: v.color,
      padding: '2px 6px',
      display: 'inline-flex', alignItems: 'center', gap: 4,
      ...style,
    }}>
      {children}
    </span>
  );
}

// ───── Hairline divider with optional index label (e.g. "01 —") ─────
function IndexRule({ index, title, right }) {
  const { t } = useTheme();
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      {index !== undefined && (
        <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>{String(index).padStart(2, '0')}</span>
      )}
      {title && (
        <span style={{ ...typeStyle('eyebrow', { type: TYPE }), color: t.inkDim }}>{title}</span>
      )}
      <div style={{ flex: 1, height: 1, background: t.rule }} />
      {right && (
        <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>{right}</span>
      )}
    </div>
  );
}

// ───── App bar (top bar for interior screens) ─────
function AppBar({ left, center, right, pad = '14px 20px' }) {
  const { t } = useTheme();
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: pad,
      borderBottom: `1px solid ${t.rule}`,
      gap: 16,
    }}>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 10 }}>{left}</div>
      <div style={{ display: 'flex', alignItems: 'center' }}>{center}</div>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 10 }}>{right}</div>
    </div>
  );
}

// ───── Logotype ─────
function Logotype({ size = 16, style = {} }) {
  const { t } = useTheme();
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      ...style,
    }}>
      <svg width={size} height={size} viewBox="0 0 16 16">
        <rect x="1" y="1" width="14" height="14" fill="none" stroke={t.ink} strokeWidth="1" />
        <rect x="4" y="4" width="8" height="8" fill={t.accent} />
        <rect x="6" y="6" width="4" height="4" fill={t.bg1} />
      </svg>
      <span style={{
        fontFamily: TYPE.serif,
        fontSize: size * 1.35,
        letterSpacing: '-0.02em',
        color: t.ink,
        fontStyle: 'italic',
      }}>notif</span>
    </div>
  );
}

// ───── Key/value row (mono, for settings & metadata) ─────
function KV({ k, v, right }) {
  const { t } = useTheme();
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', gap: 12,
      padding: '6px 0',
      borderBottom: `1px dashed ${t.rule}`,
    }}>
      <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, minWidth: 120 }}>{k}</div>
      <div style={{ ...typeStyle('body', { type: TYPE }), color: t.ink, flex: 1 }}>{v}</div>
      {right && <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>{right}</div>}
    </div>
  );
}

// ───── Status dot (pulse) ─────
function StatusDot({ color, label, style = {} }) {
  const { t } = useTheme();
  const c = color || t.accent;
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, ...style }}>
      <span style={{
        width: 6, height: 6, borderRadius: '50%',
        background: c, boxShadow: `0 0 0 3px ${c}33`,
      }} />
      {label && <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkDim }}>{label}</span>}
    </span>
  );
}

// ───── Icon — minimal line icons ─────
function Icon({ name, size = 14, color, stroke = 1.25 }) {
  const { t } = useTheme();
  const c = color || t.inkDim;
  const props = { width: size, height: size, viewBox: '0 0 16 16', fill: 'none', stroke: c, strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const paths = {
    user: <><circle cx="8" cy="5.5" r="2.5" /><path d="M2.5 14C2.5 11 5 10 8 10s5.5 1 5.5 4" /></>,
    lock: <><rect x="3" y="7" width="10" height="7" /><path d="M5.5 7V5a2.5 2.5 0 015 0v2" /></>,
    eye: <><path d="M1.5 8S4 3.5 8 3.5 14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z" /><circle cx="8" cy="8" r="2" /></>,
    search: <><circle cx="7" cy="7" r="4" /><path d="M10 10l3.5 3.5" /></>,
    bell: <><path d="M4 11V7a4 4 0 018 0v4" /><path d="M2.5 11.5h11" /><path d="M6.5 13.5a1.5 1.5 0 003 0" /></>,
    plus: <><path d="M8 3v10M3 8h10" /></>,
    x: <><path d="M3.5 3.5L12.5 12.5M12.5 3.5L3.5 12.5" /></>,
    check: <><path d="M3 8.5L6 11.5L13 4.5" /></>,
    arrow: <><path d="M3 8h10M9 4l4 4-4 4" /></>,
    menu: <><path d="M2.5 5h11M2.5 8h11M2.5 11h11" /></>,
    cog: <><circle cx="8" cy="8" r="2" /><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.5 3.5l1.4 1.4M11.1 11.1l1.4 1.4M3.5 12.5l1.4-1.4M11.1 4.9l1.4-1.4" /></>,
    link: <><path d="M6 10l4-4" /><path d="M9 4h3v3" /><path d="M7 12H4V9" /></>,
    moon: <><path d="M13 9A5 5 0 017 3c0-.5.1-1 .2-1.5A6.5 6.5 0 1014.5 9a5.5 5.5 0 01-1.5 0z" fill={c} stroke="none" /></>,
    sun: <><circle cx="8" cy="8" r="3" /><path d="M8 1.5v1.5M8 13v1.5M1.5 8H3M13 8h1.5M3.2 3.2l1 1M11.8 11.8l1 1M3.2 12.8l1-1M11.8 4.2l1-1" /></>,
    rss: <><path d="M3 3a10 10 0 0110 10" /><path d="M3 7.5a5.5 5.5 0 015.5 5.5" /><circle cx="3.5" cy="12.5" r="1" fill={c} stroke="none" /></>,
    thread: <><path d="M3.5 4.5h9M5.5 8h7M3.5 11.5h9" /></>,
    dot: <><circle cx="8" cy="8" r="3" fill={c} stroke="none" /></>,
    clock: <><circle cx="8" cy="8" r="6" /><path d="M8 4.5V8l2.5 1.5" /></>,
    star: <><path d="M8 2l1.8 3.8 4.2.5-3 2.9.7 4.2L8 11.5 4.3 13.4l.7-4.2-3-2.9 4.2-.5z" /></>,
    filter: <><path d="M2 4h12M4 8h8M6.5 12h3" /></>,
    archive: <><rect x="2" y="3" width="12" height="3" /><path d="M3.5 6v7h9V6" /><path d="M6.5 9h3" /></>,
  };
  return <svg {...props}>{paths[name] || paths.dot}</svg>;
}

Object.assign(window, {
  Eyebrow, Rule, Field, Input, Button, Checkbox, Card, CornerMarks, Tag,
  IndexRule, AppBar, Logotype, KV, StatusDot, Icon,
});
