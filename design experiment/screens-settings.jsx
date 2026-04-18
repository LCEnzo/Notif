// screens-settings.jsx — Settings / Themes screen + Empty state + Feed teaser

// ═══ Settings / Themes ═══
function Settings({ platform = 'desktop', colorway, scheme, setColorway, setScheme, texture, setTexture }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', background: t.bg0, color: t.ink }}>
      <Grain opacity={0.22} blend="overlay" scale={0.9} />

      <div style={{ position: 'relative', zIndex: 2, height: '100%', display: 'flex', flexDirection: 'column' }}>
        <AppBar
          left={<><Logotype size={mobile ? 13 : 14} /><span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>/ settings</span></>}
          right={<Icon name="x" size={13} color={t.inkDim} />}
        />

        <div style={{
          display: mobile ? 'block' : 'grid',
          gridTemplateColumns: '200px 1fr',
          flex: 1, overflow: 'hidden',
        }}>
          {/* Sidebar */}
          {!mobile && (
            <div style={{
              borderRight: `1px solid ${t.rule}`,
              padding: '24px 18px',
              display: 'flex', flexDirection: 'column', gap: 2,
            }}>
              <Eyebrow style={{ marginBottom: 14 }}>Settings</Eyebrow>
              {[
                { k: 'account', l: 'Account', n: 1 },
                { k: 'appearance', l: 'Appearance', n: 2, active: true },
                { k: 'sources', l: 'Sources', n: 3 },
                { k: 'schedule', l: 'Schedule', n: 4 },
                { k: 'notifications', l: 'Notifications', n: 5 },
                { k: 'privacy', l: 'Privacy', n: 6 },
                { k: 'shortcuts', l: 'Shortcuts', n: 7 },
                { k: 'advanced', l: 'Advanced', n: 8 },
                { k: 'about', l: 'About', n: 9 },
              ].map(i => (
                <div key={i.k} style={{
                  padding: '6px 10px',
                  display: 'flex', alignItems: 'baseline', gap: 10,
                  background: i.active ? `${t.accent}18` : 'transparent',
                  borderLeft: `2px solid ${i.active ? t.accent : 'transparent'}`,
                  cursor: 'pointer',
                }}>
                  <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, minWidth: 18 }}>
                    {String(i.n).padStart(2, '0')}
                  </span>
                  <span style={{ ...typeStyle('body', { type: TYPE }), fontSize: 13, color: i.active ? t.ink : t.inkDim }}>
                    {i.l}
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* Main */}
          <div style={{ overflow: 'auto', padding: mobile ? '20px 18px 32px' : '28px 36px 48px' }}>
            <div style={{ marginBottom: 28 }}>
              <Eyebrow style={{ color: t.accent, marginBottom: 10 }}>02 · Appearance</Eyebrow>
              <div style={{ ...typeStyle(mobile ? 'heading' : 'title', { type: TYPE }), fontStyle: 'italic', color: t.ink, marginBottom: 6 }}>
                Dress the room.
              </div>
              <div style={{ ...typeStyle('body', { type: TYPE }), color: t.inkDim, fontSize: 12 }}>
                Four colorways and a texture dial. Live preview everywhere.
              </div>
            </div>

            {/* Colorways */}
            <IndexRule index={1} title="Colorway" right={COLORWAYS[colorway].name} />
            <div style={{
              display: 'grid',
              gridTemplateColumns: mobile ? 'repeat(2, 1fr)' : 'repeat(4, 1fr)',
              gap: 10, marginTop: 14, marginBottom: 28,
            }}>
              {Object.keys(COLORWAYS).map(key => {
                const cw = COLORWAYS[key];
                const palette = cw.dark;
                const active = key === colorway;
                return (
                  <div key={key}
                    onClick={() => setColorway?.(key)}
                    style={{
                      position: 'relative',
                      border: `1px solid ${active ? t.accent : t.rule}`,
                      cursor: 'pointer',
                      background: palette.bg1,
                      aspectRatio: mobile ? '1' : '0.9',
                      overflow: 'hidden',
                  }}>
                    {/* mini preview */}
                    <div style={{
                      position: 'absolute', inset: 0,
                      background: `radial-gradient(ellipse 80% 60% at 50% 0%, ${palette.halo1}, ${palette.halo2} 30%, ${palette.halo3} 55%, ${palette.bg1} 80%)`,
                    }} />
                    {/* dot floor mini */}
                    <svg style={{ position: 'absolute', bottom: 0, left: 0, right: 0 }} width="100%" height="40" viewBox="0 0 100 40" preserveAspectRatio="none">
                      <defs>
                        <pattern id={`p-${key}`} x="0" y="0" width="4" height="4" patternUnits="userSpaceOnUse">
                          <circle cx="2" cy="2" r="0.8" fill={palette.halftone} />
                        </pattern>
                      </defs>
                      <rect width="100" height="40" fill={`url(#p-${key})`} opacity="0.6" />
                    </svg>
                    <div style={{ position: 'absolute', top: 8, left: 10, right: 10, display: 'flex', justifyContent: 'space-between' }}>
                      <span style={{ ...typeStyle('micro', { type: TYPE }), color: palette.inkDim }}>{cw.code}</span>
                      {active && <span style={{ ...typeStyle('micro', { type: TYPE }), color: palette.accent }}>● ACTIVE</span>}
                    </div>
                    <div style={{ position: 'absolute', bottom: 10, left: 10, right: 10 }}>
                      <div style={{ fontFamily: TYPE.serif, fontSize: 16, fontStyle: 'italic', color: palette.ink }}>
                        {cw.name}
                      </div>
                      <div style={{ ...typeStyle('micro', { type: TYPE }), color: palette.inkMute, textTransform: 'none', letterSpacing: 0, marginTop: 2 }}>
                        {cw.description}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Scheme */}
            <IndexRule index={2} title="Scheme" right={scheme === 'dark' ? 'Dark' : 'Light'} />
            <div style={{ display: 'flex', gap: 10, marginTop: 14, marginBottom: 28 }}>
              {['dark', 'light'].map(s => {
                const avail = !!COLORWAYS[colorway][s];
                const active = scheme === s;
                return (
                  <div key={s}
                    onClick={() => avail && setScheme?.(s)}
                    style={{
                      flex: 1,
                      padding: '14px 16px',
                      border: `1px solid ${active ? t.accent : t.rule}`,
                      background: active ? `${t.accent}10` : 'transparent',
                      cursor: avail ? 'pointer' : 'not-allowed',
                      opacity: avail ? 1 : 0.4,
                      display: 'flex', alignItems: 'center', gap: 12,
                  }}>
                    <Icon name={s === 'dark' ? 'moon' : 'sun'} size={14} color={active ? t.accent : t.inkDim} />
                    <div>
                      <div style={{ ...typeStyle('body', { type: TYPE }), fontSize: 13, color: t.ink, textTransform: 'capitalize' }}>{s}</div>
                      <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, textTransform: 'none', letterSpacing: 0 }}>
                        {avail ? (s === 'dark' ? 'Low glare, default.' : 'Paper. Daylight readable.') : 'Not available in this colorway.'}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Texture */}
            <IndexRule index={3} title="Texture" right={`${texture} / 10`} />
            <div style={{ marginTop: 14, marginBottom: 28 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                <Eyebrow>off</Eyebrow>
                <input
                  type="range" min={0} max={10} step={1}
                  value={texture}
                  onChange={(e) => setTexture?.(+e.target.value)}
                  style={{ flex: 1, accentColor: t.accent }}
                />
                <Eyebrow>full</Eyebrow>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10 }}>
                <Eyebrow style={{ color: t.inkMute, textTransform: 'none', letterSpacing: 0 }}>
                  Grain, halftone density & dithering intensity
                </Eyebrow>
              </div>
            </div>

            {/* Typography preview */}
            <IndexRule index={4} title="Typography" right="Instrument Serif · JetBrains Mono" />
            <div style={{ marginTop: 14, padding: 22, border: `1px solid ${t.rule}`, background: `${t.bg1}66`, position: 'relative' }}>
              <div style={{ fontFamily: TYPE.serif, fontSize: 42, fontStyle: 'italic', color: t.ink, lineHeight: 1, marginBottom: 10 }}>
                The signals before the noise.
              </div>
              <div style={{ fontFamily: TYPE.mono, fontSize: 12, color: t.inkDim, letterSpacing: '0.02em', lineHeight: 1.6 }}>
                Body copy is held in a monospace to echo terminal origins —<br/>
                deliberate, slightly cramped, legible at a glance.
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ═══ Empty state (post-onboarding, no notifs yet) ═══
function EmptyState({ platform = 'desktop' }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', background: t.bg0, color: t.ink }}>
      <Grain opacity={0.22} blend="overlay" scale={0.9} />

      <div style={{ position: 'relative', zIndex: 2, height: '100%', display: 'flex', flexDirection: 'column' }}>
        <AppBar
          left={<><Logotype size={mobile ? 13 : 14} /><span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>/ feed</span></>}
          right={
            <>
              <Icon name="filter" size={14} color={t.inkDim} />
              <Icon name="cog" size={14} color={t.inkDim} />
            </>
          }
        />

        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: mobile ? 24 : 40, textAlign: 'center' }}>
          {/* Dithered orb */}
          <div style={{ marginBottom: 32, opacity: 0.85 }}>
            <DitherOrb size={mobile ? 160 : 220} seed={5} />
          </div>
          <Eyebrow style={{ marginBottom: 14, color: t.accent }}>All clear</Eyebrow>
          <div style={{ ...typeStyle(mobile ? 'heading' : 'title', { type: TYPE }), fontStyle: 'italic', color: t.ink, marginBottom: 12, maxWidth: 480, textWrap: 'balance' }}>
            No new signal.
          </div>
          <div style={{ ...typeStyle('body', { type: TYPE }), color: t.inkDim, fontSize: mobile ? 12 : 13, maxWidth: 380, lineHeight: 1.7, marginBottom: 24 }}>
            Notif is listening to <span style={{ color: t.ink }}>6 sources</span>.
            The next digest arrives at <span style={{ color: t.accent }}>18:00</span>.
            Consider going outside.
          </div>
          <div style={{ display: 'flex', gap: 10, flexDirection: mobile ? 'column' : 'row' }}>
            <Button variant="ghost" size="md" prefix={<Icon name="rss" size={12} color={t.ink} />}>
              Manage sources
            </Button>
            <Button size="md" prefix={<Icon name="plus" size={12} color={t.btnInk} />}>
              Add a source
            </Button>
          </div>
        </div>

        {/* Bottom — quiet status footer */}
        <div style={{
          borderTop: `1px solid ${t.rule}`,
          padding: '10px 20px',
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        }}>
          <div style={{ display: 'flex', gap: 18 }}>
            <Eyebrow>last poll 14:32</Eyebrow>
            <Eyebrow style={{ color: t.inkMute }}>{mobile ? '' : 'next 14:47'}</Eyebrow>
          </div>
          <StatusDot label="IDLE" color={t.accent} />
        </div>
      </div>
    </div>
  );
}

// ═══ Feed teaser — the notification list, grouped by time then source ═══
function FeedTeaser({ platform = 'desktop' }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';

  const groups = [
    {
      time: 'TODAY · 14:30 digest',
      sources: [
        { src: 'hackernews', kind: 'FORUM', items: [
          { title: 'Urbit Address Space: A Planetary Ledger', meta: '324 pts · 87 comments', age: '2h' },
          { title: 'Show HN: I wrote a 6502 emulator in Zig', meta: '188 pts · 34 comments', age: '4h' },
          { title: 'Why OpenBSD is irrelevant (2016)', meta: '412 pts · 214 comments', age: '5h', hot: true },
        ]},
        { src: 'daringfireball', kind: 'RSS', items: [
          { title: '"Vision Pro Year One"', meta: 'John Gruber · link post', age: '3h' },
        ]},
      ]
    },
    {
      time: 'TODAY · 10:00 digest',
      sources: [
        { src: '/r/djangolearning', kind: 'FORUM', items: [
          { title: 'Celery vs. Dramatiq in 2026?', meta: 'u/pip_install · 22 replies', age: '6h' },
          { title: 'Postgres schema migrations without downtime', meta: 'u/vercel_refugee · 8 replies', age: '7h' },
        ]},
        { src: 'flutter/flutter', kind: 'GIT', items: [
          { title: 'v3.30.0 — adaptive Material 3 scaffolds', meta: 'release · 42 commits', age: '9h', hot: true },
        ]},
      ]
    },
    {
      time: 'YESTERDAY',
      sources: [
        { src: 'stratechery digest', kind: 'MAIL', items: [
          { title: 'The Post-Platform Era', meta: 'Ben Thompson · 3200w · 14 min', age: '1d' },
        ]},
        { src: 'kottke', kind: 'RSS', items: [
          { title: 'An atlas of marginalia, vol II', meta: 'link post', age: '1d' },
          { title: 'Time-lapse of a tide', meta: 'video · 2 min', age: '1d' },
        ]},
      ]
    },
  ];

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', background: t.bg0, color: t.ink }}>
      <Grain opacity={0.22} blend="overlay" scale={0.9} />

      <div style={{ position: 'relative', zIndex: 2, height: '100%', display: 'flex', flexDirection: 'column' }}>
        <AppBar
          left={<>
            <Logotype size={mobile ? 13 : 14} />
            <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>/ feed</span>
          </>}
          center={!mobile && <Eyebrow>9 new · by time</Eyebrow>}
          right={<>
            <Icon name="filter" size={14} color={t.inkDim} />
            <Icon name="search" size={14} color={t.inkDim} />
            <Icon name="cog" size={14} color={t.inkDim} />
          </>}
        />

        <div style={{ flex: 1, overflow: 'auto' }}>
          {groups.map((g, gi) => (
            <div key={gi}>
              <div style={{
                padding: '14px 20px 6px',
                display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
                position: 'sticky', top: 0, background: `${t.bg0}ee`, backdropFilter: 'blur(6px)',
                borderBottom: `1px solid ${t.rule}`,
                zIndex: 1,
              }}>
                <Eyebrow style={{ color: t.accent }}>{g.time}</Eyebrow>
                <Eyebrow>{g.sources.reduce((a, s) => a + s.items.length, 0)} items</Eyebrow>
              </div>
              {g.sources.map((s, si) => (
                <div key={si}>
                  <div style={{
                    padding: '10px 20px 6px',
                    display: 'flex', alignItems: 'center', gap: 10,
                  }}>
                    <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.accent, minWidth: 42 }}>{s.kind}</span>
                    <span style={{ fontFamily: TYPE.serif, fontStyle: 'italic', fontSize: 15, color: t.ink }}>{s.src}</span>
                    <div style={{ flex: 1, height: 1, background: t.rule }} />
                  </div>
                  {s.items.map((it, ii) => (
                    <div key={ii} style={{
                      padding: mobile ? '10px 20px' : '9px 20px 9px 72px',
                      display: 'flex', alignItems: 'baseline', gap: 12,
                      borderBottom: `1px dashed ${t.rule}`,
                      cursor: 'pointer',
                    }}>
                      <span style={{
                        width: 6, height: 6, borderRadius: '50%',
                        background: it.hot ? t.accent : t.inkFaint,
                        flexShrink: 0, marginTop: 6,
                      }} />
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontFamily: TYPE.serifLong, fontSize: mobile ? 14 : 15, color: t.ink, lineHeight: 1.35, marginBottom: 2 }}>
                          {it.title}
                        </div>
                        <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, textTransform: 'none', letterSpacing: 0 }}>
                          {it.meta}
                        </div>
                      </div>
                      <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, flexShrink: 0 }}>{it.age}</span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          ))}
        </div>

        <div style={{
          borderTop: `1px solid ${t.rule}`,
          padding: '10px 20px',
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        }}>
          <Eyebrow>next poll 14:47</Eyebrow>
          <StatusDot label="LIVE" color={t.accent} />
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Settings, EmptyState, FeedTeaser });
