# Plan: self-hosted F-Droid repo for Notif APKs

Status: proposal, revised 2026-10-06 after Luka's answers; planning only. The Health Connect exporter that motivates the Android build is planned separately.

## Goal

Luka's phone installs and updates Notif through the stock F-Droid client. The client points at a
self-hosted repo at `https://fdroid.lcenzo.com/repo`, which the VPS signs and serves. Nothing goes to
f-droid.org; F-Droid is only the update GUI. Updates are manual, and the repo is unlisted but not
access-controlled. Done means one command produces a signed APK in the repo, and the phone offers it
on its next refresh.

## Constraints and verified facts

Every fact was read in the cited source on 2026-10-06. *Inference* marks what was reasoned to, not observed.

| # | Fact | Source |
|---|---|---|
| F1 | The VPS is a Hetzner CX33 running Debian 13: 4 shared x86 vCPU, 8 GB RAM, 80 GB NVMe. Current free RAM and disk are not recorded anywhere in the repo. | `NOTES.md`, [vps], [hz] |
| F2 | Cloudflare proxies `notif.lcenzo.com`. Caddy already serves `*.lcenzo.com` (404) with a Cloudflare origin cert. A more specific site block beats the wildcard. | `Caddyfile`, [caddy] |
| F3 | By default Cloudflare caches `.jar` and `.apk` but not `.json`. With no `Cache-Control`, the edge keeps a response 120 min. `no-cache` responses are not cached. | [cf] |
| F4 | `applicationId` is `com.example.notif`, release builds are signed with the debug key, and the Gradle heap is `-Xmx1536M` (the template uses 8G). Flutter 3.44.0 pins compileSdk 36, minSdk 24 and NDK 28.2.13676358. | `android/app/build.gradle`, [fl] |
| F5 | `pubspec.yaml` has `version: 0.3.0` with no `+N`. Without `--build-number`, `build.gradle` falls back to versionCode `1` for every build. | [fl] `gradle_utils.dart` |
| F6 | Android refuses an update that has a lower versionCode or a different signing cert. Losing the APK key means uninstall and reinstall. | [a-ver], [a-sign] |
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

Decided by Luka on 2026-10-06: arm64 only; versionCode is `git rev-list --count`; versionName is the
pubspec semver; the host is `fdroid.lcenzo.com`; the app ID is `com.lcenzo.notif`, to confirm before
the first install.

## Options

**O1. Build paths.** Both share one publish step, and the repo index key stays on the VPS in both. The numbers are inference.

| | V. VPS (default) | G. GitHub Actions (optional) |
|---|---|---|
| Luka runs | `ssh vps notif-apk build` | the Actions tab, or `gh workflow run apk.yml --ref master`; then `ssh vps notif-apk fetch` |
| VPS load per build | 3-5 GB RAM (capped at 5 GB), 3 vCPU, 5-15 min | under 0.5 GB, seconds |
| Extra VPS disk | 4-6 GB (NDK, Gradle and pub caches) | none |
| APK key lives in | the VPS | a GitHub environment secret, plus the VPS copy if V is also used. Both paths must use the same key (F6). |
| New credentials | none | the APK key in GitHub, and a read-only PAT (personal access token) on the VPS |

**O2. Threat model, plainly.**

1. The realistic risk is a malicious or hijacked dependency: a pub package, a Gradle plugin, the Flutter SDK, or a base image. Its code lands inside the APK, and either path will sign it. Where signing happens does not change that. The defenses are the lockfile, a pinned Flutter version and image, and reading dependency bumps.
2. A stolen APK key alone does nothing to the phone. Luka updates by hand, from this repo only. To deliver code, an attacker also needs the repo, which means the index key or control of the VPS.
3. Under V, root on the VPS holds the whole chain. But root there already has all Notif data and the Health Connect exports; what it would add is code on the phone at the next manual update. G puts the APK key in one more place, GitHub, without adding a delivery route.
4. Losing a key is cheap with one phone. Losing the APK key means reinstalling Notif, logging in, and re-granting Health Connect (`allowBackup=false`, so nothing else is lost). Losing the index key means re-adding the repo with its new fingerprint. Rotating a key works the same way. `apksigner rotate` exists, but a reinstall is simpler.
5. Two free hygiene steps: build without the key, then sign in a separate step that has no network (V) or that gets the master-only environment secret (G). This keeps the key out of build-time code's direct reach. It is not a defense against item 1.

## Recommendation

1. **The default is V.** `notif-apk build` checks out `origin/master` into a throwaway `git worktree`. It runs `build-apk.sh <count>` in a build image (`FROM ghcr.io/cirruslabs/flutter:3.44.0` plus the NDK) under `--memory 5g --cpus 3` and `nice`. Then it runs `sign-apk.sh` under `--network none`, with the APK key mounted read-only, and finally `publish`.
2. **G is optional.** The workflow below runs the same two scripts on the runner and uploads the signed APK. `notif-apk fetch` uses the PAT to download the newest successful master run, then calls `publish`.
3. **The shared `notif-apk publish <apk>`** runs in a Debian trixie container with fdroidserver 2.4.2:
   a. `apksigner verify --print-certs` must match the cert SHA-256 pinned in git. This catches debug-signed or wrong-key APKs.
   b. versionCode must be higher than the newest published. An equal code is a no-op, so V and G building the same commit is harmless.
   c. It never overwrites an existing APK, prunes `repo/` to the newest 3, and runs `fdroid update`.
4. **Keys** live in `/etc/notif/fdroid/` (root, 0700; files 0600). Passwords sit in `fdroid.env` and reach fdroid through `{env:}`, so `config.yml` and `metadata/` can be committed under `deploy/fdroid/`. The backend container never mounts the keys. Both keys get an offline backup, and both fingerprints are committed. `repo/status/*.json` is public and records the command line, so secrets must never appear as arguments.
5. **Versions.** `--build-number "$(git rev-list --count HEAD)"`. It only grows, because every new master commit has the old tip as an ancestor. `build.gradle` should fail rather than fall back to `1` (F5).
6. **Builds stay out of `deploy.sh`.** A web deploy should not wait 10 min on an APK build, or fail because of one.

Flow: merge, then `notif-apk build` (or dispatch plus `fetch`), then `publish`. Cloudflare passes the
index straight through, the phone sees the update on a manual refresh or within about 4 h, and Luka taps install.

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
      - run: deploy/fdroid/build-apk.sh "$(git rev-list --count HEAD)"   # no secrets here
      - run: deploy/fdroid/sign-apk.sh
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

All of these are inference, except the image and NDK sizes (F12). Measure them on the first run.

| | V. VPS | G. GitHub |
|---|---|---|
| Peak VPS RAM | 3-5 GB, capped at 5 GB (Gradle `Xmx2g`, Kotlin in-process, 2 workers) | under 0.5 GB |
| One-time VPS disk | 4-6 GB build cache, plus about 1 GB publish image; the Flutter image is already there | about 1 GB publish image |
| Build time | 5-10 min for the image once; first APK 10-20 min, later 4-10 min | 3-8 min, plus about 1 min to fetch and publish |
| Repo disk | 3 APKs of 10-20 MB each: under 100 MB | same |

## Phased plan

1. **Phase 0: app prerequisites**, one frontend PR.
   a. Set the `applicationId` and namespace to `com.lcenzo.notif`, and move `MainActivity.kt`.
   b. Make `build.gradle` fail when no versionCode is set, and raise `org.gradle.jvmargs` to 4G (R8; *inference*).
   c. Release builds keep the debug key; signing happens afterwards.
2. **Phase 1: path V end to end** (the milestone).
   a. Generate the keys inside the publish image: `fdroid init --keystore /keys/repo-index.p12 --repo-keyalias notif-repo`, then `keytool -genkeypair -storetype pkcs12 -keyalg RSA -keysize 4096 -validity 10000`. Back both up and commit the fingerprints.
   b. Add `deploy/fdroid/`: two Dockerfiles, `build-apk.sh`, `sign-apk.sh`, `notif-apk`, `config.yml`, `metadata/`.
   c. Add the Caddy block, the compose mount and the DNS record.
   d. Build and publish, then add the repo on the phone via the QR code in `index.html` and install.
   e. Exit criterion: a trivial commit, rebuilt, shows up as an update after one refresh.
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
| Shipping `com.example.notif`. The package name is permanent. | Phase 0 fixes it before the first install. |
| Path V: an OOM kill (the VPS has no swap) or CPU contention hurts production. | Container caps and `nice`, so only the build dies. Build off-peak. |
| Gradle downloads more SDK parts during the build (*inference*). | Bake whatever the first build fetches into the image. |
| Cloudflare bot protection challenges the F-Droid client. | Test from the phone in Phase 1, and add a skip rule if needed. |
| Path G: the PAT expires, or the secret leaks. | Fetch fails loudly. Rotate per O2.4. Keep `ubuntu-24.04` pinned. |

## Open questions for Luka

1. Confirm `com.lcenzo.notif` before the first install. It is the one choice that cannot be undone.
2. What is the real headroom on the VPS? Please run `nproc; free -m; df -h /; docker system df`.
3. Is there a wildcard DNS record? Does the origin cert cover `*.lcenzo.com`? Check with `openssl x509 -noout -ext subjectAltName`.
4. Where should the key backups go: the password manager, an offline drive, or both?
5. Is Cloudflare Bot Fight Mode, or a similar challenge, enabled?
6. Should the repo use HTTP basic auth? The client supports it, and Caddy needs 3 lines. My default is no, since the APK is built from public source.

[vps]: ../operations/vps_host.md
[hz]: https://www.hetzner.com/cloud/cost-optimized/
[caddy]: https://caddyserver.com/docs/caddyfile/concepts
[cf]: https://developers.cloudflare.com/cache/concepts/default-cache-behavior/
[fl]: https://github.com/flutter/flutter/tree/3.44.0/packages/flutter_tools
[fl-and]: https://docs.flutter.dev/deployment/android
[a-ver]: https://developer.android.com/studio/publish/versioning
[a-sign]: https://developer.android.com/studio/publish/app-signing
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
