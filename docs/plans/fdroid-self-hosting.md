# Plan: self-hosted F-Droid repo for Notif APKs

Status: proposal, revised 2026-10-07 after Luka's decisions and checks on the VPS and Cloudflare; planning only. The Health Connect exporter that motivates the Android build is planned separately.

## Goal

Luka's phone installs and updates Notif through the stock F-Droid client. The client points at a
self-hosted repo at `https://fdroid.lcenzo.com/repo`, which the VPS signs and serves. Nothing goes to
f-droid.org; F-Droid is only the update GUI. Updates are manual, and the repo is unlisted but not
access-controlled. Done means one command produces a signed APK in the repo, and the phone offers it
on its next refresh.

## Constraints and verified facts

Facts were read in the cited source on 2026-10-06; F1, F2, F17 and F18 were checked on 2026-10-07. *Inference* marks what was reasoned to, not observed.

| # | Fact | Source |
|---|---|---|
| F1 | The VPS is a Hetzner CX33 running Debian 13: 4 shared x86 vCPU, 8 GB RAM, 80 GB NVMe. Measured: RAM 7757 MB, 964 MB used, 6792 MB available; 4 GB swap, 91 MB used; load average about 0.02. After a Docker cleanup: `/` 75 GB, 57 GB free; images 2.2 GB, build cache 2.2 GB. The cleanup removed `flutter:3.44.0` (F12), so the next web deploy or the first APK build pulls it again. | `NOTES.md`, [vps], [hz]; `ssh notif`: `nproc; free -m; df -h /; docker system df; uptime` |
| F2 | Cloudflare proxies `notif.lcenzo.com` and has proxied wildcard `*.lcenzo.com` A and AAAA records pointing at the VPS. `fdroid.lcenzo.com` already reaches Caddy's `*.lcenzo.com` block (404). That block's origin cert, `/etc/caddy/origin-certs/lcenzo.com.pem`, covers `*.lcenzo.com` and `lcenzo.com` and expires 2041-05-01. A more specific site block beats the wildcard. | `Caddyfile`, [caddy]; Cloudflare DNS, `curl -I`, `openssl x509` on the VPS |
| F3 | By default Cloudflare caches `.jar` and `.apk` but not `.json`. With no `Cache-Control`, the edge keeps a response 120 min. `no-cache` responses are not cached. | [cf] |
| F4 | `applicationId` is `com.example.notif`, release builds are signed with the debug key, and the Gradle heap is `-Xmx1536M` (the template uses 8G). Flutter 3.44.0 pins compileSdk 36, minSdk 24 and NDK 28.2.13676358. | `android/app/build.gradle`, [fl] |
| F5 | `pubspec.yaml` has `version: 0.3.0` with no `+N`. Without `--build-number`, `build.gradle` falls back to versionCode `1` for every build. | [fl] `gradle_utils.dart` |
| F6 | Android refuses an update that has a lower versionCode or a different signing cert. Losing the APK key means uninstall and reinstall. The application ID identifies the app on the device, so a different ID is a different app. | [a-ver], [a-sign], [a-id] |
| F7 | `fdroid init` makes `keystore.p12` (RSA 4096, mode 0600). Any string in `config.yml` can be `{env: VAR}`. | [fds] |
| F8 | `fdroid update` signs `entry.jar`, which pins `index-v2.json` by SHA-256. It also writes `index.html` with a QR code of `<repo_url>?fingerprint=…`. The client rejects a mismatched fingerprint. | [fds], [cl] `RepoAdder.kt` |
| F9 | `archive_older` defaults to 0, so APKs pile up in `repo/` until pruned. `fdroid update -c` metadata always suggests the newest APK. | [fds] |
| F10 | Debian trixie ships fdroidserver 2.4.2. I checked F7-F9 against its 2.4.2 tag. | [deb] |
| F11 | Re-signing with `apksigner` discards the existing signatures by default. So both paths can build debug-signed and sign afterwards, using build-tools 36 (present in the image and on the runner). | [apksig] |
| F12 | `ghcr.io/cirruslabs/flutter:3.44.0` (our web-build base) includes the Android SDK, build-tools 36, JDK 21 and accepted licenses, but no NDK. It is 2.28 GB compressed; the NDK download is 722 MB. | [cirrus], GHCR, [sdk] |
| F13 | GitHub runners for public repos are free: 4 vCPU, 16 GB RAM, 14 GB disk. The 24.04 image has NDK 28.2, build-tools 35/36 and android-36, but not Flutter; our CI installs it with `subosito/flutter-action`. | [gh-run], [img] |
| F14 | Downloading an Actions artifact needs a token even for a public repo; I got a 401 when testing anonymously. `Actions: read` is enough. Environment secrets with a master-only branch policy are free for public repos. | [gh-perm], [gh-env] |
| F15 | The F-Droid client's master source refreshes repos every 4 h on Wi-Fi. A manual refresh is available (*inference*). | [cl] `RepoUpdateWorker.kt` |
| F16 | Flutter release builds always run R8 (Android's code shrinker). `--target-platform android-arm64` is a valid flag. | [fl-and], [fl] |
| F17 | Bot Fight Mode is off by default, and Luka never enabled it. Requests with user agents `Dart/3.12 (dart:io)` and `F-Droid 1.21` reached the origin unchallenged: web root 200, an auth-required API path 401 from Django, no `cf-mitigated` header. Cloudflare scores each request, so a clean probe does not prove the phone passes. WAF rules cannot skip Bot Fight Mode. | [cf-bfm], [cf-bot]; `curl -I` with those user agents |
| F18 | `API_URL` defaults to `http://localhost:8000/api/v1`. The web image passes the relative `/api/v1`, which only web resolves against the page; native builds use the value as-is. `GIT_HASH` defaults to `dev`. `DEV_LOGIN_USERNAME` and `DEV_LOGIN_PASSWORD` fill a debug-login button that exists only under `kDebugMode`. | `frontend/lib/services/api_client.dart:7`, `frontend/Dockerfile:29`, `frontend/lib/screens/about.dart`, `frontend/lib/screens/login.dart` |

Decided by Luka on 2026-10-06: arm64 only; versionCode is `git rev-list --count`; versionName is the
pubspec semver; the host is `fdroid.lcenzo.com`; the app ID is `com.lcenzo.notif`. Changing the ID
later is possible but makes a new app (F6): install it, remove the old one, log in again, re-grant
Health Connect, and lose app-local settings. With one phone that is cheap. Decided on 2026-10-07: no
HTTP basic auth (O3), key backups on Luka's PC (Recommendation 4), signing inside the build script
(O2.5), and an opt-in `deploy.sh --apk` (Recommendation 7).

## Options

**O1. Build paths.** Both share one publish step, and the repo index key stays on the VPS in both. The numbers are inference.

| | V. VPS (default) | G. GitHub Actions (optional) |
|---|---|---|
| Luka runs | `ssh notif notif-apk build`, or `deploy.sh --apk` | the Actions tab, or `gh workflow run apk.yml --ref master`; then `ssh notif notif-apk fetch` |
| VPS load per build | 3-5 GB RAM (capped at 5 GB), 3 vCPU, 5-15 min | under 0.5 GB, seconds |
| Extra VPS disk | 4-6 GB (NDK, Gradle and pub caches) | none |
| APK key lives in | the VPS | a GitHub environment secret, plus the VPS copy if V is also used. Both paths must use the same key (F6). |
| New credentials | none | the APK key in GitHub, and a read-only PAT (personal access token) on the VPS |

**O2. Threat model, plainly.**

1. The realistic risk is a malicious or hijacked dependency: a pub package, a Gradle plugin, the Flutter SDK, or a base image. Its code lands inside the APK, and either path will sign it. Where signing happens does not change that. The defenses are the lockfile, a pinned Flutter version and image, and reading dependency bumps.
2. A stolen APK key alone does nothing to the phone. Luka updates by hand, from this repo only. To deliver code, an attacker also needs the repo, which means the index key or control of the VPS.
3. Under V, root on the VPS holds the whole chain. But root there already has all Notif data and the Health Connect exports; what it would add is code on the phone at the next manual update. G puts the APK key in one more place, GitHub, without adding a delivery route.
4. Losing or leaking a key, with one phone. Rotating one costs the same as losing it. `apksigner rotate` exists, but a reinstall is simpler.

   | Key | Lost | Leaked |
   |---|---|---|
   | APK signing key | Reinstall Notif, log in, re-grant Health Connect. App-local settings go too (`allowBackup=false`). | Alone, nothing (item 2). |
   | Repo index key | Re-add the repo from the new QR code in `index.html`; the installed app keeps working. | Alone, nothing: the attacker must also serve `fdroid.lcenzo.com`, and an update to Notif must carry the APK cert (F6). Both keys plus the host give code on the phone at the next manual update. |

5. Signing happens inside `build-apk.sh`, right after the build. V mounts the APK key read-only; G decodes it from the master-only environment secret. Build-time code can read it, but by item 2 the key alone cannot reach the phone, and by item 4 losing it costs one reinstall, so a separate no-network signing container would buy almost nothing. The index key never enters a build; only `publish` holds it.

**O3. HTTP basic auth: no.** The client supports it and Caddy needs 3 lines, but it would put a username and password in front of the whole repo site, stored in the F-Droid client, and hide nothing: the APK is built from public source.

## Recommendation

1. **The default is V.** `notif-apk build [commit]` checks out the commit (default `origin/master`) into a throwaway `git worktree`. It runs `build-apk.sh <versionCode> <short sha>` in a build image (`FROM ghcr.io/cirruslabs/flutter:3.44.0` plus the NDK) under `--memory 5g --memory-swap 5g --cpus 3` and `nice`, with the APK key mounted read-only. The script builds, signs with `apksigner`, and then `publish` runs. The caller computes both arguments, because a worktree's `.git` file points outside the container's mount (*inference*). Equal `--memory` and `--memory-swap` keep the build out of swap [docker-mem], so the host's 4 GB swap stays production's cushion.
2. **G is optional.** The workflow below runs the same `build-apk.sh` on the runner and uploads the signed APK. `notif-apk fetch` uses the PAT to download the newest successful master run, then calls `publish`.
3. **The shared `notif-apk publish <apk>`** runs in a Debian trixie container with fdroidserver 2.4.2:
   a. `apksigner verify --print-certs` must match the cert SHA-256 pinned in git. This catches debug-signed or wrong-key APKs.
   b. The built-in API URL must be production: `lib/arm64-v8a/libapp.so` must contain `https://notif.lcenzo.com/api/v1` and must not contain `localhost:8000`. Dart AOT keeps string literals as plain bytes, so `unzip -p` and `grep -c` suffice (*inference*; Phase 1 tests it).
   c. versionCode must be higher than the newest published. An equal code is a no-op, so V and G building the same commit is harmless.
   d. It never overwrites an existing APK, prunes `repo/` to the newest 3, and runs `fdroid update`.
4. **Keys** live in `/etc/notif/fdroid/` (root, 0700; files 0600). Passwords reach fdroid through `{env:}` and `apksigner` through `--ks-pass env:`, so `config.yml` and `metadata/` can be committed under `deploy/fdroid/`. The build container gets only the APK key and its password; publish gets only the index key and its password; the backend container mounts neither. Both fingerprints are committed. `repo/status/*.json` is public and records the command line, so secrets must never appear as arguments. The backup is the whole directory, passwords included, in `~/Documents` on Luka's PC. If Windows syncs Documents to OneDrive, that is also a cloud copy, which is acceptable at these stakes (O2.4).
5. **Versions.** `--build-number "$(git rev-list --count HEAD)"`. It only grows, because every new master commit has the old tip as an ancestor. `build.gradle` should fail rather than fall back to `1` (F5).
6. **Compile-time defines.** `build-apk.sh` passes exactly `--dart-define=API_URL=https://notif.lcenzo.com/api/v1` and `--dart-define=GIT_HASH=<short sha>` (F18). It takes no other arguments, so nothing can add the `DEV_LOGIN_*` defines; check 3b catches a build that missed the URL.
7. **`deploy.sh --apk` is opt-in.** After the web deploy finishes, it runs `notif-apk build <deployed sha>`, so web and APK come from one commit. An APK failure prints a banner and makes `deploy.sh` exit non-zero, but never undoes or blocks the web deploy, which is done by then. Without the flag, `deploy.sh` behaves as today. `notif-apk build` stays usable on its own.

Flow: merge, then `deploy.sh --apk`, `notif-apk build`, or a dispatch plus `fetch`; each ends in
`publish`. Cloudflare passes the index straight through, the phone sees the update on a manual
refresh or within about 4 h, and Luka taps install.

```yaml
on: workflow_dispatch                                # never on push or pull_request
permissions: { contents: read }
jobs:
  apk:
    if: github.ref == 'refs/heads/master'
    runs-on: ubuntu-24.04
    environment: apk-signing                         # branch policy: master only
    steps:
      - { uses: actions/checkout@v6, with: { fetch-depth: 0 } }   # rev-list needs history
      - { uses: subosito/flutter-action@v2, with: { flutter-version: '3.44.0', cache: true } }
      - run: |                                       # builds, then signs (O2.5)
          base64 -d <<<"$APK_KS_B64" > "$RUNNER_TEMP/apk.p12"
          APK_KS="$RUNNER_TEMP/apk.p12" deploy/fdroid/build-apk.sh "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
        env: { APK_KS_B64: "${{ secrets.APK_KS_B64 }}", APK_KS_PASS: "${{ secrets.APK_KS_PASS }}" }
      - { uses: actions/upload-artifact@v7, with: { name: notif-apk, path: out/*.apk, retention-days: 7 } }
```

```caddy
fdroid.lcenzo.com {
	tls {$FALLBACK_TLS_CERT} {$FALLBACK_TLS_KEY}
	root * /srv/fdroid                      # compose: /srv/notif-fdroid/repo:/srv/fdroid/repo:ro
	@index path /repo/entry.jar /repo/entry.json /repo/index-v1.jar /repo/index-v1.json /repo/index-v2.json /repo/diff/* /repo/index.html /repo/index.png
	header @index Cache-Control "no-cache"
	@apk path *.apk
	header @apk Cache-Control "public, max-age=31536000, immutable"
	file_server
}
```

## Resource estimates

All of these are inference, except the image and NDK sizes (F12) and the VPS figures (F1). Measure them on the first run.

| | V. VPS | G. GitHub |
|---|---|---|
| Peak VPS RAM | 3-5 GB, capped at 5 GB with no swap (Gradle `-Xmx3g`, Kotlin in-process, 2 workers). Of 6.8 GB available, about 1.6 GB stays free, plus 4 GB swap. | under 0.5 GB |
| One-time VPS disk | 4-6 GB build cache, about 1 GB publish image, and `flutter:3.44.0` (2.28 GB compressed), which the web build shares but the cleanup removed (F1). 57 GB is free. | about 1 GB publish image |
| Build time | 5-10 min for the image once, plus the `flutter:3.44.0` pull unless a web deploy got there first; first APK 10-20 min, later 4-10 min | 3-8 min, plus about 1 min to fetch and publish |
| Repo disk | 3 APKs of 10-20 MB each: under 100 MB | same |

## Phased plan

1. **Phase 0: app prerequisites**, one frontend PR.
   a. Set the `applicationId` and namespace to `com.lcenzo.notif`, and move `MainActivity.kt`.
   b. Make `build.gradle` fail when no versionCode is set, and set `org.gradle.jvmargs=-Xmx3g` (repo today 1536M, template 8G; R8 needs more, *inference*). That fits the 5 GB cap; Phase 1d measures it.
   c. Release builds keep the debug key; signing happens afterwards.
2. **Phase 1: path V end to end** (the milestone).
   a. Generate the keys inside the publish image: `fdroid init --keystore /keys/repo-index.p12 --repo-keyalias notif-repo`, then `keytool -genkeypair -storetype pkcs12 -keyalg RSA -keysize 4096 -validity 10000`. Copy `/etc/notif/fdroid/` to `~/Documents` on Luka's PC and commit the fingerprints.
   b. Add `deploy/fdroid/`: two Dockerfiles, `build-apk.sh`, `notif-apk`, `config.yml`, `metadata/`. Add `--apk` to `deploy.sh`.
   c. Add the Caddy block and the compose mount. DNS and the origin cert already cover the host (F2).
   d. Build and publish, then add the repo on the phone via the QR code in `index.html` and install. Record the first build's peak memory (`docker stats`, or the cgroup's `memory.peak`) and adjust the heap or the cap from it.
   e. Sign one APK built without the `API_URL` define, with a higher versionCode. Publish must refuse it and name check 3b.
   f. From the phone, check that the F-Droid client refreshes and the app logs in and loads data. A 403 or an HTML page where JSON belongs means a challenge (F17).
   g. Exit criterion: a trivial commit, rebuilt, shows up as an update after one refresh.
3. **Phase 2: path G.**
   a. Add `apk.yml` and an `apk-signing` environment that only master can use, holding the two secrets.
   b. Create a fine-grained PAT limited to this repo, with `Actions: read` and an expiry.
   c. Add `notif-apk fetch`.
4. **Phase 3:** a section in `vps_host.md`, and one key-restore drill.

## Risks

| Risk | Mitigation |
|---|---|
| Cloudflare keeps `entry.jar` for 2 h (F3), so the update stays invisible or the index hash mismatches. | Per-file `Cache-Control`, as in the snippet. Check `cf-cache-status` with `curl -I`. |
| A missing build number gives versionCode 1 (F5). A master rewrite lowers the count (F6). | Gradle fails without a number. Publish refuses any code not higher than the last. Never force-push master. |
| The same versionCode is republished with new bytes while the old APK sits in the edge cache. | Publish never overwrites an APK. |
| An APK ships with the default `localhost` API URL or debug-login defines (F18). | `build-apk.sh` fixes the defines and takes no extras. Publish refuses an APK without the production URL (3b). |
| Shipping `com.example.notif`; a later ID change makes a new app (F6). | Phase 0 fixes it before the first install. A later change costs a reinstall, a login, the Health Connect grants and app-local settings. |
| Path V: the build starves production of RAM or CPU. | At the measured load (F1) a 5 GB cap leaves about 1.6 GB free plus 4 GB swap, and `--cpus 3` leaves a core. With no swap of its own, the build dies by OOM rather than thrashing. |
| Gradle downloads more SDK parts during the build (*inference*). | Bake whatever the first build fetches into the image. |
| Cloudflare challenges the F-Droid client or the app's API calls. | Probes passed (F17); the phone test in Phase 1 is the real check. Leave Bot Fight Mode off, since WAF rules cannot skip it. If another feature challenges, add a skip rule for that host. |
| Path G: the PAT expires, or the secret leaks. | Fetch fails loudly. Rotate per O2.4. Keep `ubuntu-24.04` pinned. |

## Open questions for Luka

None as of 2026-10-07. What remains unknown gets tested in Phase 1 (steps 1e and 1f), not decided.

[vps]: ../operations/vps_host.md
[hz]: https://www.hetzner.com/cloud/cost-optimized/
[caddy]: https://caddyserver.com/docs/caddyfile/concepts
[cf]: https://developers.cloudflare.com/cache/concepts/default-cache-behavior/
[cf-bfm]: https://developers.cloudflare.com/bots/get-started/bot-fight-mode/
[cf-bot]: https://developers.cloudflare.com/bots/concepts/bot-score/
[docker-mem]: https://docs.docker.com/engine/containers/resource_constraints/
[fl]: https://github.com/flutter/flutter/tree/3.44.0/packages/flutter_tools
[fl-and]: https://docs.flutter.dev/deployment/android
[a-ver]: https://developer.android.com/studio/publish/versioning
[a-sign]: https://developer.android.com/studio/publish/app-signing
[a-id]: https://developer.android.com/build/configure-app-module
[fds]: https://gitlab.com/fdroid/fdroidserver/-/tree/2.4.2/fdroidserver
[cl]: https://gitlab.com/fdroid/fdroidclient/-/tree/master
[deb]: https://packages.debian.org/trixie/fdroidserver
[apksig]: https://android.googlesource.com/platform/tools/apksig/+/refs/heads/main/src/main/java/com/android/apksig/
[cirrus]: https://github.com/cirruslabs/docker-images-flutter/blob/master/sdk/Dockerfile
[sdk]: https://dl.google.com/android/repository/repository2-3.xml
[gh-run]: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
[img]: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
[gh-perm]: https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens
[gh-env]: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
