# F-Droid repo runbook

The self-hosted F-Droid repo at `https://fdroid.lcenzo.com/repo` (Phase 1 of the plan in
PR #113, `docs/plans/fdroid-self-hosting.md` on branch `docs/plan-fdroid-hosting`).
`./deploy.sh` sets up and checks the VPS side on every run, through
`deploy/fdroid/notif-apk setup`. This runbook covers only what code cannot do: moving the
keys to and from Luka's PC, committing the pins, the phone, and the one-time Phase 1
checks. If a step's output differs from what it says to expect, stop and report; do not
improvise around it.

| Where | How |
|---|---|
| VPS | `ssh notif`, as `luka`; `./deploy.sh` asks for the sudo password |
| Luka's PC | Git Bash, in the repo checkout |
| Phone | the F-Droid client |

## Layout

| What | Where |
|---|---|
| Signing keys | `/etc/notif/fdroid/` (root, 0700): `apk.p12`, `apk.pass`, `repo-index.p12`, `repo-index.pass` (root, 0600) |
| Key backups | `~/Documents/notif-fdroid-keys-<date>.tar` on Luka's PC |
| Cert pins | `deploy/fdroid/pins/apk-cert.sha256`, `deploy/fdroid/pins/repo-index-cert.sha256` |
| Served repo | `/srv/notif-fdroid/repo` (root, 0755), mounted read-only into Caddy at `/srv/fdroid/repo` |
| Tool | `/usr/local/bin/notif-apk` -> `deploy/fdroid/notif-apk` in the checkout |
| Images | `notif-apk-publish` (built by `setup`), `notif-apk-build` (built by the first `notif-apk build`) |
| Caches | Docker volumes `notif-apk-gradle`, `notif-apk-pub`; throwaway worktrees in `~/.cache/notif-apk` |

The build container gets only `apk.p12` and `apk.pass`; the publish container gets only
`repo-index.p12` and `repo-index.pass`. Passwords are read from those files inside the
containers and never appear on a command line: `repo/status/*.json` is public and records
the `fdroid` command line.

## What `./deploy.sh` does

After the web deploy (`=== Deploy complete ===`), `deploy.sh` runs
`deploy/fdroid/notif-apk setup`, which:

1. creates `/etc/notif/fdroid` and `/srv/notif-fdroid/repo` with the owners and modes above.
   On a fresh VPS, Compose creates `/srv/notif-fdroid/repo` first, as root 0755, when it
   starts Caddy with the mount;
2. points `/usr/local/bin/notif-apk` at the checkout's `deploy/fdroid/notif-apk`;
3. builds the `notif-apk-publish` image (a cached no-op after the first time);
4. brings the signing keys to the state the pins describe:

| Keys in `/etc/notif/fdroid` | Pins | `setup` |
|---|---|---|
| all four files | set | checks both certs against the pins; refuses on a mismatch, never overwrites |
| none | empty | generates both keys and prints their digests and the next steps |
| none | set | with `--fdroid-restore <tar>`, restores from that backup and checks it against the pins; without it, refuses |
| all four files | empty | prints the digests and the next steps; never regenerates |
| none | empty, with `--fdroid-restore <tar>` | restores from that backup without a check, then prints the digests |
| one to three files | any | refuses |
| any | only one set | refuses |

The keys are RSA 4096, SHA256withRSA, 10000 days, PKCS12, with aliases `notif-apk`
(`CN=Notif APK`) and `notif-repo` (`CN=notif-repo, OU=F-Droid`); the index key uses the
parameters `fdroid init` would. Each password is 32 random bytes in base64, in its `.pass`
file. `fdroid init` itself is not used: in fdroidserver 2.4.2 it ignores `--keystore` when
generating, writing `./keystore.p12` while `config.yml` points elsewhere, and it stores the
password in `config.yml`.

If `setup` fails, `deploy.sh` prints an `F-DROID HOST SETUP FAILED` banner and exits 1.
The web deploy has already completed and stays in place. With `--apk`, the build is
skipped. Fix the cause and run `./deploy.sh` again; nothing has to be undone first.

## First-ever setup

Preconditions: both PRs are merged to `master`: Phase 0 (app ID `com.lcenzo.notif`) and
the one that added this file.

1. On the VPS, deploy:

   ```bash
   cd /home/luka/notif
   ./deploy.sh
   ```

   After `=== Deploy complete ===` and `=== F-Droid host setup ===`, expect two
   `Generating 4,096 bit RSA key pair` lines and a framed block naming
   `deploy/fdroid/backup-keys.sh` and two `echo <64 hex> >>deploy/fdroid/pins/...` lines.
   The two digests must differ. `deploy.sh` exits 0.

2. On the PC, back the keys up:

   ```bash
   cd ~/"Notif - Copy"
   deploy/fdroid/backup-keys.sh
   ```

   It runs `notif-apk export-keys` on the VPS, copies the tar to
   `~/Documents/notif-fdroid-keys-<date>.tar`, and shreds the VPS copy. Expect two
   `backup-keys: sha256 <hash>` lines with the same hash, a listing of `fdroid/apk.p12`,
   `fdroid/apk.pass`, `fdroid/repo-index.p12` and `fdroid/repo-index.pass`, and
   `backup-keys: backed up to ...`. `~/Documents` is the local `C:\Users\LCEnzo\Documents`
   (checked 2026-10-08; it is not redirected to OneDrive). Back up first: once the pins are
   committed, a lost key can only be replaced by a rotation.

3. On the PC, commit the pins on a branch, using the two `echo` lines from step 1:

   ```bash
   git fetch origin
   git worktree add .claude/worktrees/fdroid-pins -b chore/fdroid-pins origin/master
   cd .claude/worktrees/fdroid-pins
   echo <APK digest> >>deploy/fdroid/pins/apk-cert.sha256
   echo <repo index digest> >>deploy/fdroid/pins/repo-index-cert.sha256
   git diff
   ```

   `git diff` must show exactly one added line of 64 hex digits in each file. Then:

   ```bash
   git commit -a -F - <<'EOF'
   Pin the F-Droid signing cert digests

   Adds the SHA-256s of the APK and repo index signing certs that
   notif-apk setup generated on the VPS. notif-apk refuses to build or
   publish until both are set.
   EOF
   git push -u origin chore/fdroid-pins
   gh pr create --base master --title "Pin the F-Droid signing cert digests" \
     --body "Adds the cert SHA-256s from docs/operations/fdroid_runbook.md, first-ever setup."
   ```

4. After Luka merges the PR, on the VPS:

   ```bash
   cd /home/luka/notif
   ./deploy.sh --apk
   ```

   Expect `notif-apk: the keys in /etc/notif/fdroid match the pins`, then the first build.
   It builds `notif-apk-build` (pulls `ghcr.io/cirruslabs/flutter:3.44.0`, about 2.3 GB
   compressed, unless a web deploy already has it, plus the NDK, about 0.7 GB) and fills
   the Gradle and pub caches. On disk the two images take about 13 GB together (the Flutter
   base about 7 GB of that, shared with the web build). Expect, near the end:

   ```text
   build-apk: signed /build/out/notif-<versionCode>-<sha>.apk
   notif-apk: build memory: anon peak <A> MiB (sampled every 2 s), memory.peak <P> MiB (includes page cache); memory.events: low 0 high 0 max <M> oom 0 oom_kill 0 oom_group_kill 0
   publish: check 3a passed: signed by the pinned APK key
   publish: check 3b passed: built against https://notif.lcenzo.com/api/v1
   publish: check 3c passed: versionCode <versionCode> (<versionName>) > 0
   publish: check 3d passed: com.lcenzo.notif_<versionCode>.apk is new
   <date> WARNING: repo_icon "repo/icons/icon.png" does not exist! Check "config.yml".
   <date> INFO: Creating signed index with this key (SHA256):
   <date> INFO: <the repo index pin, in upper case, in pairs>
   <date> WARNING: repo_icon "repo/icons/icon.png" does not exist, generating placeholder.
   <date> INFO: Finished
   publish: published com.lcenzo.notif_<versionCode>.apk
   ```

   The two `repo_icon` warnings appear on the first publish only.

5. Add the repo on the phone (below), then run the Phase 1 checks.

## Phone: add the repo and install

1. On the PC, open `https://fdroid.lcenzo.com/repo/` in a browser. The page shows a QR
   code (`index.png`) for `https://fdroid.lcenzo.com/repo?fingerprint=<FINGERPRINT>`, the
   repo index pin in upper case.
2. On the phone, in F-Droid: Settings, Repositories, the `+` button, and scan the QR code.
   These menu labels were not checked against a phone; if they differ, use the client's
   "add repository" entry.
3. Before confirming, compare the fingerprint the client shows with
   `deploy/fdroid/pins/repo-index-cert.sha256`, ignoring case and spacing. They must match.
4. Confirm, wait for the refresh, find Notif, and install it. Android asks once to allow
   F-Droid to install apps.

## Phase 1 checks (once)

**Memory and time (plan 1d).** Record the `anon peak` from the first build's memory line,
and its duration, in the Phase 1 notes; `anon peak` is the number to size the heap and the
cap from. `memory.peak` counts page cache, which grows until the 5 GB limit, so it says
little on its own. The build runs under `--memory 5g --memory-swap 5g --cpus 3`; if
`oom_kill` is not 0 or the build died, stop and report the line.

**Caching.** Check what Cloudflare and Caddy serve:

```bash
n=$(git -C /home/luka/notif rev-list --count origin/master)
ls -la /srv/notif-fdroid/repo
for p in index-v2.json entry.jar index.jar index.html "com.lcenzo.notif_$n.apk" "com.lcenzo.notif_$n.apk"; do
  echo "== $p"
  curl -sSI "https://fdroid.lcenzo.com/repo/$p" | grep -iE '^(HTTP|cache-control|cf-cache-status)'
done
```

Expect `HTTP/2 200` for each. `index-v2.json`, `entry.jar`, `index.jar` and `index.html`
carry `cache-control: no-cache` and a `cf-cache-status` other than `HIT`. The APK carries
`cache-control: public, max-age=31536000, immutable`; its second request may show `HIT`.

**Leftovers.**

```bash
docker ps -a --filter name=notif-apk --format '{{.Names}}'
ls -A ~/.cache/notif-apk
git -C /home/luka/notif worktree list
```

Expect no containers, an empty directory, and only `/home/luka/notif` in the worktree list.

**Negative test: a build without the API URL (plan 1e).** Build an APK without the
`API_URL` define, signed with the real APK key and with a versionCode one above the
published one, then try to publish it. This bypasses `build-apk.sh` on purpose, since that
script always passes the define.

```bash
cd /home/luka/notif
git fetch origin
mkdir -p /home/luka/.cache/notif-apk
neg=$(mktemp -d /home/luka/.cache/notif-apk/negtest.XXXXXX)
git worktree add --detach "$neg/src" origin/master
vc=$(( $(git rev-list --count origin/master) + 1 ))
docker run --rm --name notif-apk-negtest \
  --memory 5g --memory-swap 5g --cpus 3 \
  --mount type=bind,src="$neg/src",dst=/src,readonly \
  --mount type=bind,src="$neg",dst=/out \
  --mount type=bind,src=/etc/notif/fdroid/apk.p12,dst=/run/secrets/apk.p12,readonly \
  --mount type=bind,src=/etc/notif/fdroid/apk.pass,dst=/run/secrets/apk.pass,readonly \
  --mount type=volume,src=notif-apk-gradle,dst=/root/.gradle \
  --mount type=volume,src=notif-apk-pub,dst=/root/.pub-cache \
  notif-apk-build bash -euo pipefail -c '
mkdir /build && cp -a /src/. /build/ && rm -f /build/.git
cd /build/frontend
flutter build apk --release --target-platform android-arm64 --build-number "$1"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" sign --ks /run/secrets/apk.p12 \
  --ks-key-alias notif-apk --ks-pass file:/run/secrets/apk.pass --v4-signing-enabled false \
  --out /out/negtest.apk build/app/outputs/flutter-apk/app-release.apk' negtest "$vc"
ls /srv/notif-fdroid/repo/*.apk
notif-apk publish "$neg/negtest.apk"; echo "exit=$?"
ls /srv/notif-fdroid/repo/*.apk
```

Expect, from `notif-apk publish`:

```text
publish: check 3a passed: signed by the pinned APK key
publish: REFUSED: check 3b: libapp.so does not contain https://notif.lcenzo.com/api/v1
exit=1
```

and the same APK list before and after. Clean up:

```bash
git -C /home/luka/notif worktree remove --force "$neg/src"
rm -rf "$neg"
```

If publish did not refuse, the repo now offers a broken APK. Do not install it; stop and
report, and leave the repo as it is for diagnosis.

**Phone check (plan 1f).**

1. In F-Droid, pull down on the Latest or Updates tab to refresh. It must finish without
   an error about the Notif repo.
2. Open Notif, log in, and open the feed. It must load data.

If either fails, a Cloudflare challenge is the first suspect (plan F17). On the VPS,
see whether the phone's API calls reached the origin and what they got:

```bash
docker compose -f /home/luka/notif/compose.yaml --profile prod exec -T caddy \
  sh -c 'grep "dart:io" /var/log/caddy/access.json | tail -n 5'
```

No lines while the app shows an error means Cloudflare stopped the requests; lines with
`"status":403` or HTML responses mean the same at the edge or a WAF rule. Report what you
see; do not change Cloudflare settings from this runbook.

**Exit criterion (plan 1g).** Merge any trivial commit to `master`, then on the VPS run
`./deploy.sh --apk`. Expect the publish lines from step 4 of the first-ever setup. On the
phone, refresh F-Droid once: Notif must show an update. Install it and open the app.

## Restore on a fresh VPS

Preconditions: the host is set up as in `deploy.md` up to its first `./deploy.sh` (checkout
at `/home/luka/notif`, `.env` files, origin certificates), and the pins are on `master`.

1. On the PC, copy the newest backup to the VPS:

   ```bash
   scp ~/Documents/notif-fdroid-keys-<date>.tar notif:
   ```

2. On the VPS, deploy with the restore, and the APK build, since a fresh repo is empty:

   ```bash
   cd /home/luka/notif
   ./deploy.sh --apk --fdroid-restore ~/notif-fdroid-keys-<date>.tar
   ```

   Expect `notif-apk: restored; the keys in /etc/notif/fdroid match the pins`, then the
   build and publish lines from step 4 of the first-ever setup.

3. On the VPS, remove the copy: `shred -u ~/notif-fdroid-keys-<date>.tar`.

The phone needs nothing: the repo fingerprint and the APK key are the same, so a refresh
in F-Droid picks the repo up again.

## Key rotation

Rotate both keys together, and only for a reason (a leaked key, or a lost key with the
pins already committed). Every phone has to uninstall Notif, losing its local data, and
add the repo again: Android refuses an update signed by another key, and the F-Droid client
refuses an index signed by another key.

1. On a branch, delete the 64-hex line from both pin files, and merge.
2. On the VPS, retire the old keys and the APKs they signed. The repo directory stays,
   because Caddy's mount holds on to it; only its contents move:

   ```bash
   d=$(date +%F)
   sudo mv /etc/notif/fdroid "/etc/notif/fdroid.retired-$d"
   sudo install -d -m 0700 "/srv/notif-fdroid/repo.retired-$d"
   sudo find /srv/notif-fdroid/repo -mindepth 1 -maxdepth 1 -exec mv -t "/srv/notif-fdroid/repo.retired-$d" -- {} +
   ```

3. Run the first-ever setup from step 1. Its step 4 publishes into the empty repo.
4. On each phone: uninstall Notif, remove the repo in F-Droid, then add the repo and
   install as above.
5. Once the new setup works, delete the retired directories on the VPS. Keep the old
   backup tars only as long as a rollback is worth it.

## Another backup copy

Run `deploy/fdroid/backup-keys.sh` on the PC at any time. A second run on the same day
refuses, because the file name exists; rename the first one.

## Refusals and what they mean

| Message | Meaning | Action |
|---|---|---|
| `refused: pin missing: ...` | the pins are not committed yet | finish the first-ever setup |
| `refused: only one of deploy/fdroid/pins/... has a value` | a pin file was edited by hand | set both pins or neither |
| `refused: ... is not a lowercase SHA-256 hex digest` | a malformed pin | fix the pin file |
| `refused: the APK key in /etc/notif/fdroid has cert SHA-256 X, but the pin is Y` (or `the repo index key`) | the keys on disk are not the pinned ones; `setup` never overwrites them | report. If the pins are right, set the keys aside with `sudo mv /etc/notif/fdroid /etc/notif/fdroid.aside-$(date +%F)` and restore (restore on a fresh VPS, steps 1-3). Never edit the pins to match unknown keys |
| `refused: /etc/notif/fdroid holds no keys, but the pins are set` | a fresh VPS, or the keys were removed | restore on a fresh VPS |
| `refused: /etc/notif/fdroid holds only ... of the four key files` | an interrupted restore or a manual change | report; then set the directory aside and restore, as two rows up |
| `refused: cannot read the keys in /etc/notif/fdroid` | a keystore does not open with its password file | report; then set the directory aside and restore, as three rows up |
| `notif-apk keys: the backup's ... cert SHA-256 is X, the pin is Y; installed nothing` | the tar given to `--fdroid-restore` is from another key set | use the backup that matches the pins |
| `notif-apk keys: the backup does not hold ...` or `cannot read ... with ...` | the tar is damaged or not a key backup | use another backup |
| `refused: ... notif-fdroid-keys.tar exists, left by an earlier export` | an earlier `backup-keys.sh` run stopped half-way | `ssh notif shred -u notif-fdroid-keys.tar`, then run `backup-keys.sh` again |
| `warning: ... notif-fdroid-keys.tar still holds a copy of the keys` | the same, noticed by `setup` | the same |
| `backup-keys: refused: ... exists; an earlier backup has that name` | a second backup on the same day | rename the first one |
| `backup-keys: the hashes differ` or `does not hold exactly the four key files` | the copy is damaged; both copies are left | report |
| `REFUSED: repo index key cert SHA-256 ... does not match the pin` | `/etc/notif/fdroid/repo-index.p12` is not the pinned key | stop; restore from a backup |
| `REFUSED: check 3a: ...` | debug-signed, signed with another key, or more than one signer | stop; the APK key or the build is wrong |
| `REFUSED: check 3b: ...` | built without the production `API_URL` | rebuild with `notif-apk build` |
| `check 3c: versionCode N is already published; nothing to do` | same commit published before (exit 0) | none |
| `REFUSED: check 3c: ... lower than the newest published` | an older commit, or `master` was rewritten | build a newer commit; never force-push `master` |
| `REFUSED: check 3d: ... already exists in repo/` | a stray APK not in the index, left by an interrupted publish | report; remove only after confirming it is not in `index-v2.json` |
| `another notif-apk run is in progress` | another build, publish, key generation or restore holds the lock | wait for it |
| `REFUSED: publish failed (see the output above); restored repo/ to its state before this run` | `fdroid update` (or moving an APK) failed after the checks passed; the new APK was removed, and the pruned APKs and the old index files were put back | report the `fdroid` output above it; the repo still serves what it served before |
| `REFUSED: publish failed, and so did restoring repo/; it is now inconsistent` | the restore failed too; pruned APKs that were not put back are lost | stop; do not refresh F-Droid on the phone; report the whole output |

To reset the build caches (for example after a Flutter upgrade):
`docker volume rm notif-apk-gradle notif-apk-pub`.
