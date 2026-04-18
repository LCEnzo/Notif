// screens-onboarding.jsx — First-run onboarding flow (3 steps)
// Uses a calmer backdrop — subtle grain, no halftone floor.

// ═══ Onboarding chrome wrapper ═══
function OnbChrome({ step, total, title, subtitle, right, children, platform }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', background: t.bg0, color: t.ink }}>
      {/* Subtle backdrop */}
      <div style={{
        position: 'absolute', inset: 0,
        background: `radial-gradient(ellipse 80% 50% at 50% 0%, ${t.halo3}88 0%, ${t.bg1} 45%, ${t.bg0} 80%)`,
      }} />
      <Grain opacity={0.28} blend="overlay" scale={0.9} />
      <Grain opacity={0.14} blend="multiply" scale={2.2} contrast={160} />

      <div style={{
        position: 'relative', zIndex: 2,
        width: '100%', height: '100%',
        display: 'flex', flexDirection: 'column',
        padding: mobile ? '22px 18px 22px' : '28px 44px',
      }}>
        {/* Top rail */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <Logotype size={mobile ? 13 : 15} />
            <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>/ setup</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            {Array.from({ length: total }).map((_, i) => (
              <span key={i} style={{
                width: i + 1 === step ? 18 : 8, height: 2,
                background: i + 1 <= step ? t.accent : t.rule,
                transition: 'all 0.2s',
              }} />
            ))}
            <Eyebrow style={{ marginLeft: 10 }}>{String(step).padStart(2, '0')} / {String(total).padStart(2, '0')}</Eyebrow>
          </div>
        </div>

        {/* Step header */}
        <div style={{ marginTop: mobile ? 28 : 46, marginBottom: mobile ? 22 : 30, maxWidth: 640 }}>
          <Eyebrow style={{ marginBottom: 10, color: t.accent }}>{right}</Eyebrow>
          <div style={{
            ...typeStyle(mobile ? 'heading' : 'title', { type: TYPE }),
            fontStyle: 'italic',
            color: t.ink,
            marginBottom: 10,
            textWrap: 'balance',
          }}>{title}</div>
          <div style={{ ...typeStyle('body', { type: TYPE }), color: t.inkDim, fontSize: mobile ? 12 : 13, maxWidth: 520 }}>
            {subtitle}
          </div>
        </div>

        <div style={{ flex: 1, overflow: 'auto' }}>{children}</div>
      </div>
    </div>
  );
}

// ═══ Step 02 — Sources ═══
function OnbSources({ platform = 'desktop' }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';

  const sources = [
    { kind: 'RSS', name: 'Daring Fireball', url: 'daringfireball.net/feeds/main', status: 'on', vol: 'LO' },
    { kind: 'RSS', name: 'Kottke', url: 'kottke.org/index.xml', status: 'on', vol: 'MED' },
    { kind: 'FORUM', name: 'Hacker News', url: 'news.ycombinator.com', status: 'on', vol: 'HI', filter: '> 150 pts' },
    { kind: 'FORUM', name: '/r/DjangoLearning', url: 'reddit.com/r/djangolearning', status: 'on', vol: 'LO' },
    { kind: 'RSS', name: 'Ribbonfarm', url: 'ribbonfarm.com/feed', status: 'off', vol: '—' },
    { kind: 'GIT', name: 'flutter/flutter', url: 'github.com/flutter/flutter', status: 'on', vol: 'MED', filter: 'releases only' },
    { kind: 'MAIL', name: 'Stratechery digest', url: 'notif+strat@lcenzo.net', status: 'on', vol: 'LO' },
  ];

  return (
    <OnbChrome
      platform={platform}
      step={2} total={3} right="Configure · Feeds"
      title="Tell me what's worth watching."
      subtitle="Notif polls each source and batches what matters into your feed. You can always prune later."
    >
      <div style={{ display: 'grid', gridTemplateColumns: mobile ? '1fr' : '1fr 220px', gap: mobile ? 14 : 28 }}>
        {/* List */}
        <div style={{ border: `1px solid ${t.rule}`, background: `${t.bg1}88` }}>
          <div style={{
            display: 'grid',
            gridTemplateColumns: mobile ? '60px 1fr 50px' : '60px 1fr 120px 60px 30px',
            padding: '10px 14px', borderBottom: `1px solid ${t.rule}`,
            ...typeStyle('micro', { type: TYPE }), color: t.inkMute,
          }}>
            <div>kind</div>
            <div>source</div>
            {!mobile && <div>filter</div>}
            {!mobile && <div style={{ textAlign: 'right' }}>vol</div>}
            <div style={{ textAlign: 'right' }}>on</div>
          </div>
          {sources.map((s, i) => (
            <div key={i} style={{
              display: 'grid',
              gridTemplateColumns: mobile ? '60px 1fr 50px' : '60px 1fr 120px 60px 30px',
              padding: '12px 14px',
              borderBottom: i < sources.length - 1 ? `1px dashed ${t.rule}` : 'none',
              alignItems: 'center',
              opacity: s.status === 'off' ? 0.5 : 1,
            }}>
              <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.accent }}>{s.kind}</div>
              <div>
                <div style={{ ...typeStyle('body', { type: TYPE }), color: t.ink, fontSize: 13 }}>{s.name}</div>
                <div style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute, textTransform: 'none', letterSpacing: 0 }}>{s.url}</div>
              </div>
              {!mobile && (
                <div style={{ ...typeStyle('micro', { type: TYPE }), color: s.filter ? t.inkDim : t.inkMute, textTransform: 'none', letterSpacing: 0 }}>
                  {s.filter || '—'}
                </div>
              )}
              {!mobile && (
                <div style={{ textAlign: 'right', ...typeStyle('micro', { type: TYPE }), color: t.inkDim }}>{s.vol}</div>
              )}
              <div style={{ textAlign: 'right' }}>
                <Checkbox checked={s.status === 'on'} />
              </div>
            </div>
          ))}
          <div style={{ padding: 14, borderTop: `1px solid ${t.rule}` }}>
            <Button variant="ghost" size="sm" prefix={<Icon name="plus" size={11} color={t.ink} />}>Add source</Button>
          </div>
        </div>

        {/* Side panel */}
        {!mobile && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <div style={{ padding: 16, border: `1px solid ${t.rule}`, background: `${t.bg2}66`, position: 'relative' }}>
              <CornerMarks color={t.ruleStrong} />
              <Eyebrow style={{ marginBottom: 8 }}>Schedule</Eyebrow>
              <div style={{ ...typeStyle('body', { type: TYPE }), color: t.ink, fontSize: 12 }}>
                Poll every 15 min · digest 3× daily
              </div>
            </div>
            <div style={{ padding: 16, border: `1px solid ${t.rule}`, background: `${t.bg2}66`, position: 'relative' }}>
              <CornerMarks color={t.ruleStrong} />
              <Eyebrow style={{ marginBottom: 8 }}>Discovery</Eyebrow>
              <div style={{ ...typeStyle('body', { type: TYPE }), color: t.inkDim, fontSize: 12, lineHeight: 1.5 }}>
                Import OPML, or paste a list of URLs. Notif will detect feeds automatically.
              </div>
              <Button size="sm" variant="ghost" style={{ marginTop: 10 }}>Import OPML</Button>
            </div>
          </div>
        )}
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 22 }}>
        <Button variant="ghost" size="md" prefix={<Icon name="arrow" size={11} color={t.ink} style={{ transform: 'rotate(180deg)' }} />}>
          Back
        </Button>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <Eyebrow>6 of 7 selected</Eyebrow>
          <Button size="md" suffix={<Icon name="arrow" size={11} color={t.btnInk} />}>
            Continue
          </Button>
        </div>
      </div>
    </OnbChrome>
  );
}

// ═══ Step 03 — Rhythm ═══
function OnbRhythm({ platform = 'desktop' }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';

  const options = [
    { k: 'calm', title: 'Calm', body: 'Three digests a day. Never interrupts.', rec: true },
    { k: 'reactive', title: 'Reactive', body: 'Batches every 30 min. Buzzes for starred sources.' },
    { k: 'live', title: 'Live', body: 'Notifies in real time. You decide what\'s urgent.' },
  ];

  return (
    <OnbChrome
      platform={platform}
      step={3} total={3} right="Configure · Rhythm"
      title="Choose a pace for your feed."
      subtitle="This sets how often Notif pings you. You can tune it per source later."
    >
      <div style={{ display: 'grid', gridTemplateColumns: mobile ? '1fr' : 'repeat(3, 1fr)', gap: 14 }}>
        {options.map((o, i) => (
          <div key={o.k} style={{
            padding: 20,
            border: `1px solid ${o.rec ? t.accent : t.rule}`,
            background: o.rec ? `${t.bg2}aa` : `${t.bg1}66`,
            position: 'relative',
            cursor: 'pointer',
          }}>
            {o.rec && <CornerMarks color={t.accent} />}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
              <Eyebrow>{String(i + 1).padStart(2, '0')}</Eyebrow>
              {o.rec && <Eyebrow style={{ color: t.accent }}>RECOMMENDED</Eyebrow>}
            </div>
            <div style={{ ...typeStyle('heading', { type: TYPE }), fontStyle: 'italic', color: t.ink, marginBottom: 8 }}>
              {o.title}
            </div>
            <div style={{ ...typeStyle('body', { type: TYPE }), color: t.inkDim, fontSize: 12, lineHeight: 1.6 }}>
              {o.body}
            </div>
            {/* visualization */}
            <div style={{ marginTop: 18, height: 32, display: 'flex', alignItems: 'end', gap: 2 }}>
              {Array.from({ length: 24 }).map((_, h) => {
                const heights = {
                  calm: [0,0,0,0,0,0,0,0, 18,0,0,0, 22,0,0,0,0,0, 14,0,0,0,0,0],
                  reactive: [2,1,0,1,2,3,5,7,9,12,14,14,16,14,12,14,16,18,14,10,7,5,3,2],
                  live: [3,5,2,4,3,8,12,22,28,24,20,22,25,28,30,26,24,28,32,20,15,10,8,5],
                };
                const h2 = heights[o.k][h];
                return (
                  <div key={h} style={{
                    flex: 1,
                    height: h2 || 1,
                    background: h2 ? (o.rec ? t.accent : t.inkDim) : t.rule,
                    opacity: h2 ? (o.rec ? 1 : 0.6) : 0.3,
                  }} />
                );
              })}
            </div>
            <Eyebrow style={{ marginTop: 8 }}>00:00 — 24:00</Eyebrow>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 24, padding: 20, border: `1px solid ${t.rule}`, background: `${t.bg2}44`, position: 'relative' }}>
        <Eyebrow style={{ marginBottom: 10 }}>Quiet hours</Eyebrow>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Eyebrow>From</Eyebrow>
            <div style={{ ...typeStyle('body', { type: TYPE }), color: t.ink, borderBottom: `1px solid ${t.ruleStrong}`, padding: '2px 8px', minWidth: 60 }}>22:30</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Eyebrow>Until</Eyebrow>
            <div style={{ ...typeStyle('body', { type: TYPE }), color: t.ink, borderBottom: `1px solid ${t.ruleStrong}`, padding: '2px 8px', minWidth: 60 }}>07:00</div>
          </div>
          <div style={{ flex: 1 }} />
          <Checkbox checked={true} label="Weekends stay quiet" />
        </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 22 }}>
        <Button variant="ghost" size="md" prefix={<Icon name="arrow" size={11} color={t.ink} style={{ transform: 'rotate(180deg)' }} />}>
          Back
        </Button>
        <Button size="md" suffix={<Icon name="arrow" size={11} color={t.btnInk} />}>
          Finish setup
        </Button>
      </div>
    </OnbChrome>
  );
}

Object.assign(window, { OnbSources, OnbRhythm, OnbChrome });
