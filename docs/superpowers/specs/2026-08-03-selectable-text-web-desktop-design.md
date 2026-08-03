# App-wide text selection on web and desktop

Date: 2026-08-03. Status: design, ready to implement. Scope: frontend only.

## Why

Flutter web paints to canvas, so nothing on screen is DOM text. Ordinary `Text`
widgets are therefore unselectable and uncopyable unless Flutter itself provides
a selection mechanism. The concrete failure that prompted this: `StartingPage`
(`frontend/lib/screens/starting.dart:33`) renders `BACKEND UNREACHABLE` plus an
`AuthUnavailable.reason` string, and a user hitting that screen on web cannot
copy the reason into a bug report. The same applies to every diagnostic string
the app renders as plain `Text`.

The codebase has been patching this one widget at a time — `SelectableText` at
six call sites in `homescreen.dart`, two in `ops.dart`, a `SelectionArea` in
`about.dart:110` and another in `auth_chrome.dart:308`. That is folklore
maintenance: every new screen silently reintroduces the defect, and nothing
fails when it does. Selection should be an ambient property of the app on
platforms where users expect it, not a per-widget opt-in someone must remember.

## Decision

Wrap the entire routed widget tree in a single `SelectionArea`, installed via
the `MaterialApp.router` `builder` hook, gated to web and desktop. Mobile keeps
its native feel: on Android/iOS, ambient long-press-to-select over all app
chrome is wrong, and mobile users are not the ones filing bug reports with
pasted stack traces.

Rejected alternative: converting `Text` to `SelectableText` case by case. It is
strictly more code, it is opt-in (so it decays), and `SelectableText` is a
read-only `EditableText` — heavier than a `RenderParagraph` participating in a
selection registrar, and it cannot select across widget boundaries.

## Insertion point

Two files change.

**New: `frontend/lib/commons/selection_scope.dart`.** Holds the pure gating
predicate, the `TransitionBuilder`-shaped entry point, and a `SelectionScope`
widget. It lives in `commons/` because that is where shared UI primitives live
per `AGENTS.md`, and because a leaf file is directly pumpable in a widget test
where `App` is not (see Test plan).

Shape (illustrative, not final code):

```dart
/// Pure so the truth table is testable; `kIsWeb` is a compile-time constant
/// and `defaultTargetPlatform` is ambient, and neither is injectable at a
/// call site.
@visibleForTesting
bool selectionEnabledFor({required bool isWeb, required TargetPlatform platform}) =>
    isWeb ||
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.linux ||
    platform == TargetPlatform.macOS;

Widget selectionScopeBuilder(BuildContext context, Widget? child) =>
    SelectionScope(child: child ?? const SizedBox.shrink());
```

`SelectionScope` reads `selectionEnabledFor(isWeb: kIsWeb, platform:
defaultTargetPlatform)` and returns either `SelectionArea(child: child)` or
`child` unchanged.

This mirrors the existing idiom: `dither_overlay.dart` extracts
`ditherOverlayPaletteFor` as a pure function precisely so the gated widget's
logic is unit-testable, and `dither_overlay_test.dart` tests exactly that.

**Changed: `frontend/lib/main.dart:148`.** The `MaterialApp.router(...)` call
currently passes `title`, `theme`, `routerConfig` and nothing else — **there is
no existing `builder` argument to compose with**, so this is a one-line
addition placed immediately after `title: 'Notif',` (line 149):

```dart
builder: selectionScopeBuilder,
```

plus one import. There is exactly one `MaterialApp`/`WidgetsApp` in
`frontend/lib/` (verified: `main.dart:148` is the only match), so one wrapper
covers the whole app. The `MaterialApp` instances in `frontend/test/` are test
harnesses and are deliberately unaffected.

### Why the builder hook is the right altitude

`MaterialApp` invokes the user `builder` *inside* its own `ScaffoldMessenger`,
`DefaultSelectionStyle` and `AnimatedTheme`, and passes the router's `Navigator`
as `child`. Two consequences, both wanted:

- The `SelectionArea` sits above the `Navigator` and below the theme. It
  survives route changes (no rebuild churn on navigation), and `Theme.of` works
  inside it.
- Everything routed is covered, including `StartingPage` — the screen that
  motivated this — and dialogs pushed onto the root navigator, since routes and
  overlay entries live inside that `Navigator`. Confidence high; the dialog case
  is worth one manual check (see Rollout).

`child` is typed `Widget?` by `TransitionBuilder`. It is non-null in practice
here, but the null-coalesce above is free and avoids a `!`.

## Gating predicate

`kIsWeb` is checked **first and independently**, not as a fallback. On web,
`defaultTargetPlatform` reports the *mimicked host OS* — a mobile browser
reports `android`/`iOS`. Ordering the check the other way would silently
disable selection in mobile browsers, which is exactly where someone copying an
error message is most likely to be. Accepted consequence: mobile-browser users
get long-press selection with handles. That is normal web behavior, not a
defect.

`TargetPlatform.fuchsia` is excluded — the app does not ship there, and
guessing at its input conventions is unfounded.

## What is already in place

- **Selection colors: done, no theme gap.** `notif_theme.dart:57-61` already
  defines `textSelectionTheme` with `cursorColor: tokens.accent`,
  `selectionColor: tokens.accent.withValues(alpha: 0.32)` and
  `selectionHandleColor: tokens.accent`, built per colorway. `MaterialApp`
  propagates that into `DefaultSelectionStyle`, which `SelectionArea` resolves
  against, so the highlight follows the active palette on every colorway with
  no change here.
- **Architecture tests do not constrain this.** `test/architecture_test.dart`
  enforces four boundaries only: secure storage, Dio ownership, hand-built
  `Authorization` headers, browser-cookie reads. Nothing restricts where UI
  wrappers live, and this change touches none of them.

## Edge cases

Matters:

- **Existing nested `SelectionArea`s** (`about.dart:110`,
  `auth_chrome.dart:308`). Both stay. On mobile they are the *only* thing making
  that text selectable, so removing them regresses mobile; nesting is legal, and
  the worst case on web/desktop is that a drag cannot span the inner region's
  boundary. Verify the about page manually; if a cross-boundary drag misbehaves,
  that is a follow-up, not a blocker for this change.
- **Drag over buttons and labels highlights their text.** Real, mildly
  untidy, and the accepted price of ambient selection. Taps are unaffected:
  `SelectableRegion` competes in the gesture arena with a pan/long-press
  recognizer and does not consume taps, so `NotifButton` keeps working.
- **Touch scrolling inside the wrapped tree on mobile web.** Scrollables should
  keep winning touch drags, with selection requiring long-press first. This is
  the one behavior worth deliberate manual verification, because getting it
  wrong makes lists unscrollable on phones.

Non-issues, with reasoning:

- **Text fields.** `EditableText` manages its own selection and does not
  register with the selection registrar, so `TextField` and `SelectableText` are
  untouched by the ambient region.
- **`DitherOverlay`.** Returns `SizedBox.shrink()` on web
  (`dither_overlay.dart:13`) and is `IgnorePointer`-wrapped on desktop, so it
  neither absorbs drags nor contributes selectable text.
- **Right-click on web.** Whether the browser's native menu or Flutter's
  adaptive selection toolbar appears is decided by Flutter's web defaults, which
  this change does not touch — it is the same behavior the existing
  `SelectionArea` on the about page already gets. Either menu offers Copy, and
  Ctrl+C is the path the acceptance check actually exercises, so no work is
  planned here.
- **Ctrl+C.** `SelectableRegion` registers copy shortcuts on desktop and web,
  which is the point of the change.
- **Idle performance.** Cost is one gesture detector plus one registrar
  insert/remove per visible `RenderParagraph` on mount/unmount. Linear in
  visible `Text` widgets, negligible below thousands, and zero on mobile where
  the wrapper is not built at all.

## Test plan

New file `frontend/test/selection_scope_test.dart`, roughly 40 lines:

1. **Truth table** (plain `test`, no pumping): `selectionEnabledFor` returns
   true for `isWeb: true` regardless of platform — asserted explicitly with
   `TargetPlatform.android` to pin the mobile-browser case — and for
   `windows`/`linux`/`macOS` when `isWeb: false`; false for `android`, `iOS`
   and `fuchsia` when `isWeb: false`.
2. **Widget gating**: pump `MaterialApp(home: SelectionScope(child: Text('x')))`
   with `debugDefaultTargetPlatformOverride = TargetPlatform.windows` and assert
   `find.byType(SelectionArea)` is `findsOneWidget`; repeat with
   `TargetPlatform.android` and assert `findsNothing`. Reset the override in
   `tearDown`.

`kIsWeb` is `false` under `flutter test` on the VM, which is why the predicate
takes `isWeb` as a parameter rather than reading the constant directly — it is
the only way to cover the web branch without a browser test runner.

Existing tests are unaffected: `starting_page_test.dart` and friends build their
own bare `MaterialApp` harnesses and never construct `App`, so no golden or
finder shifts. Full `flutter test --no-pub`, `flutter analyze --no-pub` and
`dart format .` still gate the change.

## Rollout and risks

Single commit, no feature flag, no pubspec change, no backend change. The
gating predicate is the rollback lever: if desktop behavior is wrong, narrow it
to `isWeb` alone; if everything is wrong, drop the one `builder:` line.

Manual verification after implementing, in order of information gained:

1. `flutter run -d chrome`, force the failure screen (point the backend URL at a
   dead host), drag-select `BACKEND UNREACHABLE` and the reason string, Ctrl+C,
   paste. This is the acceptance criterion.
2. Scroll a long list on a narrow Chrome window with touch emulation — confirm
   scrolling still wins over selection.
3. Open the about page and the `auth_chrome` error dialog, confirm selection
   works and the nested regions do not fight the ambient one.

Residual risk is low and cosmetic: the plausible failure modes are stray
highlighting on chrome text and the nested-region boundary, neither of which
can break auth, data, or navigation.

## Out of scope

Deliberately not done here, listed so they are not silently forgotten:

- Converting the existing `SelectableText` call sites in `homescreen.dart` and
  `ops.dart` to plain `Text`. They keep working; the conversion is a cleanup
  with a nonzero regression surface and no user-visible payoff.
- Removing the redundant `SelectionArea` wrapping a `SelectableText` at
  `auth_chrome.dart:308`. That one is redundant today, independent of this
  change.
- A custom `contextMenuBuilder`, "copy all diagnostics" affordances, or any
  selection behavior on Android/iOS.
