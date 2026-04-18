// screens-auth.jsx — Landing + Login + Register screens
// These retain the signature grain + halftone backdrop.

// ═══════════════════════════════════════════════════════════════
// Auth Landing — the first-open screen
// ═══════════════════════════════════════════════════════════════
function AuthLanding({ platform = 'desktop' }) {
  const { t, cwMeta } = useTheme();
  const mobile = platform === 'mobile';

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', color: t.ink }}>
      <SignatureBackdrop haloHeight={mobile ? '45%' : '55%'} floorHeight={mobile ? 280 : 340}>
        {/* Content */}
        <div style={{
          position: 'relative', zIndex: 2,
          width: '100%', height: '100%',
          display: 'flex', flexDirection: 'column',
          padding: mobile ? '28px 24px 32px' : '40px 56px 48px',
        }}>
          {/* Top rail */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Logotype size={mobile ? 14 : 16} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <Eyebrow>{cwMeta.code} · {cwMeta.name}</Eyebrow>
              <StatusDot label="SYNCED" />
            </div>
          </div>

          {/* Middle — display + tagline */}
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', paddingBottom: mobile ? 100 : 0 }}>
            <div style={{ maxWidth: mobile ? '100%' : 520 }}>
              <Eyebrow style={{ marginBottom: 16, color: t.accent }}>A Quiet Aggregator</Eyebrow>
              <div style={{
                ...typeStyle(mobile ? 'title' : 'display', { type: TYPE }),
                fontStyle: 'italic',
                color: t.ink,
                marginBottom: mobile ? 14 : 18,
                textWrap: 'balance',
              }}>
                The signals<br/>
                <span style={{ color: t.accent, fontStyle: 'italic' }}>before the noise.</span>
              </div>
              <div style={{
                ...typeStyle('body', { type: TYPE }),
                color: t.inkDim,
                maxWidth: 360,
                fontSize: mobile ? 12 : 13,
                lineHeight: 1.6,
              }}>
                Aggregates updates from the forums, feeds, and niche sites you
                actually read — so your phone stops asking for your attention.
              </div>
            </div>
          </div>

          {/* Bottom — auth actions */}
          <div style={{
            position: 'relative', zIndex: 3,
            display: 'flex', flexDirection: 'column', gap: 14,
            maxWidth: mobile ? '100%' : 440,
          }}>
            <IndexRule title="Begin" right="01" />
            <div style={{ display: 'flex', flexDirection: mobile ? 'column' : 'row', gap: 10 }}>
              <Button block={mobile} size="lg" style={{ flex: 1, minWidth: 160 }} suffix={<Icon name="arrow" size={12} color={t.btnInk} />}>
                Login
              </Button>
              <Button block={mobile} size="lg" variant="ghost" style={{ flex: 1, minWidth: 160 }}>
                Register
              </Button>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 4 }}>
              <Eyebrow>v0.4.2 · self-hosted</Eyebrow>
              <Eyebrow style={{ opacity: 0.7 }}>↵ to continue</Eyebrow>
            </div>
          </div>
        </div>
      </SignatureBackdrop>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Login — form overlaid on backdrop
// ═══════════════════════════════════════════════════════════════
function AuthLogin({ platform = 'desktop' }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';
  const [showPwd, setShowPwd] = React.useState(false);
  const [remember, setRemember] = React.useState(true);
  const [user, setUser] = React.useState('LCEnzo');
  const [pwd, setPwd] = React.useState('••••••••••••');

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', color: t.ink }}>
      <SignatureBackdrop haloHeight={mobile ? '45%' : '55%'} floorHeight={mobile ? 280 : 340}>
        <div style={{
          position: 'relative', zIndex: 2,
          width: '100%', height: '100%',
          display: 'flex', flexDirection: 'column',
          padding: mobile ? '28px 20px 28px' : '32px 48px',
        }}>
          {/* Top rail */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <Logotype size={mobile ? 14 : 16} />
              <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>/ login</span>
            </div>
            <Eyebrow>esc to leave</Eyebrow>
          </div>

          {/* Form card, centered */}
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{
              width: mobile ? '100%' : 420,
              position: 'relative',
              background: `linear-gradient(180deg, ${t.bg2}f2, ${t.bg1}e6)`,
              border: `1px solid ${t.ruleStrong}`,
              padding: mobile ? '24px 22px 22px' : '28px 30px 26px',
              backdropFilter: 'blur(8px)',
            }}>
              <CornerMarks color={t.accent} />
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 22 }}>
                <div style={{ ...typeStyle('heading', { type: TYPE }), color: t.ink, fontStyle: 'italic' }}>
                  Welcome back
                </div>
                <Eyebrow>01 / auth</Eyebrow>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 22 }}>
                <Field label="Handle" meta="required">
                  <Input
                    value={user}
                    prefix={<Icon name="user" size={13} />}
                    onChange={(e) => setUser(e.target.value)}
                  />
                </Field>
                <Field label="Passphrase" meta="required">
                  <Input
                    value={pwd}
                    type={showPwd ? 'text' : 'password'}
                    prefix={<Icon name="lock" size={13} />}
                    suffix={
                      <span onClick={() => setShowPwd(!showPwd)} style={{ cursor: 'pointer' }}>
                        <Icon name="eye" size={13} color={showPwd ? t.accent : t.inkMute} />
                      </span>
                    }
                    onChange={(e) => setPwd(e.target.value)}
                  />
                </Field>

                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 2 }}>
                  <Checkbox checked={remember} onChange={() => setRemember(!remember)} label="Remember this device" />
                  <a style={{ ...typeStyle('micro', { type: TYPE }), color: t.accent, cursor: 'pointer' }}>
                    forgot?
                  </a>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 4 }}>
                  <Button block size="lg" suffix={<Icon name="arrow" size={12} color={t.btnInk} />}>
                    Log in
                  </Button>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <Rule />
                    <Eyebrow style={{ whiteSpace: 'nowrap' }}>or</Eyebrow>
                    <Rule />
                  </div>
                  <Button block variant="ghost" size="lg">
                    Create account
                  </Button>
                </div>
              </div>
            </div>
          </div>

          {/* Bottom rail */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 12 }}>
            <Eyebrow>notif.local:8443</Eyebrow>
            <StatusDot label="CONNECTED" color={t.accent} />
          </div>
        </div>
      </SignatureBackdrop>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Register — fuller form
// ═══════════════════════════════════════════════════════════════
function AuthRegister({ platform = 'desktop' }) {
  const { t } = useTheme();
  const mobile = platform === 'mobile';

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', color: t.ink }}>
      <SignatureBackdrop haloHeight={mobile ? '40%' : '50%'} floorHeight={mobile ? 240 : 300}>
        <div style={{
          position: 'relative', zIndex: 2,
          width: '100%', height: '100%',
          display: 'flex', flexDirection: 'column',
          padding: mobile ? '28px 20px 28px' : '32px 48px',
        }}>
          {/* Top rail */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <Logotype size={mobile ? 14 : 16} />
              <span style={{ ...typeStyle('micro', { type: TYPE }), color: t.inkMute }}>/ register</span>
            </div>
            <Eyebrow>step 01 / 03</Eyebrow>
          </div>

          {/* Form card */}
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{
              width: mobile ? '100%' : 480,
              position: 'relative',
              background: `linear-gradient(180deg, ${t.bg2}f2, ${t.bg1}e6)`,
              border: `1px solid ${t.ruleStrong}`,
              padding: mobile ? '24px 22px 22px' : '28px 32px 26px',
              backdropFilter: 'blur(8px)',
            }}>
              <CornerMarks color={t.accent} />
              <div style={{ marginBottom: 22 }}>
                <Eyebrow style={{ marginBottom: 6 }}>Genesis</Eyebrow>
                <div style={{ ...typeStyle('heading', { type: TYPE }), color: t.ink, fontStyle: 'italic' }}>
                  Make your handle.
                </div>
                <div style={{ ...typeStyle('body', { type: TYPE }), color: t.inkMute, fontSize: 12, marginTop: 4 }}>
                  Everything stays on your server. No email, no recovery.
                </div>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
                <Field label="Handle" meta="lowercase, 3–20">
                  <Input value="lcenzo" prefix={<span style={{ ...typeStyle('body', { type: TYPE }), color: t.inkMute }}>@</span>} />
                </Field>
                <div style={{ display: 'flex', gap: 14, flexDirection: mobile ? 'column' : 'row' }}>
                  <div style={{ flex: 1 }}>
                    <Field label="Passphrase" meta="min 12">
                      <Input value="correct horse" type="password" prefix={<Icon name="lock" size={13} />} />
                    </Field>
                  </div>
                  <div style={{ flex: 1 }}>
                    <Field label="Confirm">
                      <Input value="correct horse" type="password" prefix={<Icon name="lock" size={13} />} />
                    </Field>
                  </div>
                </div>

                {/* Strength meter */}
                <div>
                  <div style={{ display: 'flex', gap: 3, marginBottom: 6 }}>
                    {[0,1,2,3,4].map(i => (
                      <div key={i} style={{
                        flex: 1, height: 2,
                        background: i < 4 ? t.accent : t.rule,
                      }} />
                    ))}
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <Eyebrow>strength</Eyebrow>
                    <Eyebrow style={{ color: t.accent }}>strong · 80%</Eyebrow>
                  </div>
                </div>

                <Field label="Recovery seed" hint="You'll see this once. Write it down.">
                  <div style={{
                    background: t.bg0, padding: '10px 12px',
                    border: `1px solid ${t.rule}`,
                    fontFamily: TYPE.mono, fontSize: 11, color: t.inkDim,
                    letterSpacing: '0.08em', lineHeight: 1.6,
                    wordBreak: 'break-all',
                  }}>
                    cedar · halibut · orbit · plough · quiver<br/>
                    · reservoir · sable · tidal · umbra · vellum
                  </div>
                </Field>

                <Checkbox checked={true} label="I've stored the seed somewhere I trust." />

                <Button block size="lg" suffix={<Icon name="arrow" size={12} color={t.btnInk} />}>
                  Continue to sources
                </Button>
              </div>
            </div>
          </div>
        </div>
      </SignatureBackdrop>
    </div>
  );
}

Object.assign(window, { AuthLanding, AuthLogin, AuthRegister });
