# F-Droid repo: Phase 1 runbook

This runbook brings up the self-hosted F-Droid repo at `https://fdroid.lcenzo.com/repo`
(Phase 1 of the plan in PR #113, `docs/plans/fdroid-self-hosting.md` on branch
`docs/plan-fdroid-hosting`). Each step is written to be run as is. If a step's output
differs from what it says to expect, stop and report; do not improvise around it.

Three places are involved:

| Where | How | Steps |
|---|---|---|
| VPS | `ssh notif`, as `luka` (docker group); `sudo` asks for the password | 0, a-f, the diagnosis in h, i |
| Luka's PC | Git Bash | b, c |
| Phone | the F-Droid client | g, h, i |

## Layout

| What | Where |
|---|---|
| Signing keys | `/etc/notif/fdroid/` (root, 0700): `apk.p12`, `apk.pass`, `repo-index.p12`, `repo-index.pass` (root, 0600) |
| Key backup | `~/Documents/notif-fdroid-keys-<date>.tar` on Luka's PC |
| Cert pins | `deploy/fdroid/pins/apk-cert.sha256`, `deploy/fdroid/pins/repo-index-cert.sha256` |
| Served repo | `/srv/notif-fdroid/repo`, mounted read-only into Caddy at `/srv/fdroid/repo` |
| Tool | `/usr/local/bin/notif-apk` -> `/home/luka/notif/deploy/fdroid/notif-apk` |
| Images | `notif-apk-build`, `notif-apk-publish`; `notif-apk` rebuilds them from `deploy/fdroid/*.Dockerfile` (cached) |
| Caches | Docker volumes `notif-apk-gradle`, `notif-apk-pub`; throwaway worktrees in `~/.cache/notif-apk` |

The build container gets only `apk.p12` and `apk.pass`; the publish container gets only
`repo-index.p12` and `repo-index.pass`. Passwords are read from those files inside the
containers and never appear on a command line: `repo/status/*.json` is public and records
the `fdroid` command line.

## 0. Preconditions

Both PRs are merged to `master`: Phase 0 (app ID `com.lcenzo.notif`) and the one that added
this file. Deploy them, which also brings the Caddy site block and the compose mount:

```bash
ssh notif
cd /home/luka/notif
./deploy.sh
```

Expect `=== Deploy complete ===`. Then check:

```bash
grep -c 'applicationId "com.lcenzo.notif"' frontend/android/app/build.gradle
test -x deploy/fdroid/notif-apk && echo notif-apk present
docker compose -f compose.yaml --profile prod exec -T caddy ls -ld /srv/fdroid/repo
```

Expect `1`, `notif-apk present`, and a directory listing for `/srv/fdroid/repo`.

## a. Generate the keys (root)

Build the publish image, create the key directory, and check it is empty:

```bash
cd /home/luka/notif
docker build --quiet --tag notif-apk-publish - < deploy/fdroid/publish.Dockerfile
sudo install -d -m 0700 -o root -g root /etc/notif/fdroid
sudo ls -A /etc/notif/fdroid
```

The last command must print nothing. If it lists files, stop: keys already exist.

Generate both keys inside the publish image. Each password is 32 random bytes in base64,
written straight to its file:

```bash
docker run --rm --network none \
  --mount type=bind,src=/etc/notif/fdroid,dst=/keys \
  notif-apk-publish bash -euo pipefail -c '
umask 077
cd /keys
for f in apk.p12 apk.pass repo-index.p12 repo-index.pass; do
  if [ -e "$f" ]; then echo "refusing: /etc/notif/fdroid/$f exists" >&2; exit 1; fi
done
head -c 32 /dev/urandom | base64 -w0 >apk.pass
head -c 32 /dev/urandom | base64 -w0 >repo-index.pass
keytool -genkeypair -keystore apk.p12 -storetype pkcs12 -alias notif-apk \
  -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 \
  -dname "CN=Notif APK" -storepass:file apk.pass -keypass:file apk.pass
keytool -genkeypair -keystore repo-index.p12 -storetype pkcs12 -alias notif-repo \
  -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 \
  -dname "CN=notif-repo, OU=F-Droid" -storepass:file repo-index.pass -keypass:file repo-index.pass
chmod 0600 apk.p12 apk.pass repo-index.p12 repo-index.pass'
sudo ls -la /etc/notif/fdroid
```

Expect two `Generating 4,096 bit RSA key pair` lines, then `drwx------ root root` for the
directory and `-rw------- root root` for the four files.

The index key uses the parameters `fdroid init` would use (RSA 4096, SHA256withRSA,
10000 days, PKCS12, `CN=notif-repo, OU=F-Droid`). `fdroid init` itself is not used:
in fdroidserver 2.4.2 it ignores `--keystore` when generating, writing `./keystore.p12`
while `config.yml` points elsewhere, and it stores the password in `config.yml`.

## b. Back up the keys to Luka's PC

On the VPS, pack the directory into a file only `luka` can read, and print its hash:

```bash
sudo tar -C /etc/notif -cf /home/luka/notif-fdroid-keys.tar fdroid
sudo chown luka:luka /home/luka/notif-fdroid-keys.tar
chmod 0600 /home/luka/notif-fdroid-keys.tar
sha256sum /home/luka/notif-fdroid-keys.tar
```

On the PC, in Git Bash:

```bash
backup=~/Documents/notif-fdroid-keys-$(date +%F).tar
if [ -e "$backup" ]; then echo "exists, stop: $backup"; else scp notif:notif-fdroid-keys.tar "$backup"; fi
sha256sum "$backup"
tar -tvf "$backup"
```

If the first line prints `exists, stop`, stop: an earlier backup has that name. The hash
must equal the VPS hash. The listing must show `fdroid/` and the four files.
`~/Documents` is the local `C:\Users\LCEnzo\Documents` (checked 2026-10-08; it is not
redirected to OneDrive).

Back on the VPS, delete the temporary copy:

```bash
shred -u /home/luka/notif-fdroid-keys.tar
```

## c. Commit the fingerprints

On the VPS, write both cert SHA-256s (not secret) to files `luka` can read:

```bash
install -d -m 0755 /home/luka/notif-fdroid-pins
docker run --rm --network none \
  --mount type=bind,src=/etc/notif/fdroid,dst=/keys,readonly \
  --mount type=bind,src=/home/luka/notif-fdroid-pins,dst=/out \
  notif-apk-publish bash -euo pipefail -c '
keytool -exportcert -keystore /keys/apk.p12 -alias notif-apk -storepass:file /keys/apk.pass \
  | sha256sum | cut -d" " -f1 >/out/apk-cert.sha256
keytool -exportcert -keystore /keys/repo-index.p12 -alias notif-repo -storepass:file /keys/repo-index.pass \
  | sha256sum | cut -d" " -f1 >/out/repo-index-cert.sha256'
cat /home/luka/notif-fdroid-pins/apk-cert.sha256 /home/luka/notif-fdroid-pins/repo-index-cert.sha256
```

Expect two lines of 64 lowercase hex digits, and they must differ.

On the PC, in Git Bash, append them to the committed pin files on a new branch and open a PR:

```bash
cd ~/"Notif - Copy"
git fetch origin
git worktree add .claude/worktrees/fdroid-pins -b chore/fdroid-pins origin/master
cd .claude/worktrees/fdroid-pins
ssh notif cat notif-fdroid-pins/apk-cert.sha256 >> deploy/fdroid/pins/apk-cert.sha256
ssh notif cat notif-fdroid-pins/repo-index-cert.sha256 >> deploy/fdroid/pins/repo-index-cert.sha256
git diff
```

`git diff` must show exactly one added line of 64 hex digits in each file. Then:

```bash
git commit -a -F - <<'EOF'
Pin the F-Droid signing cert digests

Adds the SHA-256s of the APK and repo index signing certs that step a
of docs/operations/fdroid_runbook.md generated on the VPS. notif-apk
refuses to build or publish until both are set.
EOF
git push -u origin chore/fdroid-pins
gh pr create --base master --title "Pin the F-Droid signing cert digests" \
  --body "Adds the cert SHA-256s from docs/operations/fdroid_runbook.md step c."
```

After Luka merges the PR, on the VPS:

```bash
git -C /home/luka/notif pull --ff-only
grep -hv '^#' /home/luka/notif/deploy/fdroid/pins/*.sha256
rm -r /home/luka/notif-fdroid-pins
```

`grep` must print the same two lines as above, in the order apk, then repo index.

## d. Install notif-apk on the VPS

```bash
sudo ln -sfn /home/luka/notif/deploy/fdroid/notif-apk /usr/local/bin/notif-apk
sudo install -d -m 0755 -o root -g root /srv/notif-fdroid /srv/notif-fdroid/repo
command -v notif-apk
notif-apk --help
```

Expect `/usr/local/bin/notif-apk` and the usage text. The symlink means `git pull` and
`./deploy.sh` keep the installed tool current; there is nothing to reinstall later.

## e. First build and publish (plan 1d)

```bash
time notif-apk build
```

The first run builds `notif-apk-build` (pulls `ghcr.io/cirruslabs/flutter:3.44.0`, about
2.3 GB compressed, unless a web deploy already has it, plus the NDK, about 0.7 GB) and
fills the Gradle and pub caches. On disk the two images take about 13 GB together (the
Flutter base about 7 GB of that, shared with the web build). Expect, near the end:

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

Record the `anon peak` and the `real` time from `time` in the Phase 1 notes; `anon peak`
is the number to size the heap and the cap from. `memory.peak` counts page cache, which
grows until the 5 GB limit, so it says little on its own. The build runs under
`--memory 5g --memory-swap 5g --cpus 3`; if `oom_kill` is not 0 or the build died, stop
and report the line.

Check what Cloudflare and Caddy serve:

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

Check that nothing is left behind:

```bash
docker ps -a --filter name=notif-apk --format '{{.Names}}'
ls -A ~/.cache/notif-apk
git -C /home/luka/notif worktree list
```

Expect no containers, an empty directory, and only `/home/luka/notif` in the worktree list.

## f. Negative test: a build without the API URL (plan 1e)

Build an APK without the `API_URL` define, signed with the real APK key and with a
versionCode one above the published one, then try to publish it. This bypasses
`build-apk.sh` on purpose, since that script always passes the define.

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

## g. Add the repo on the phone

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

## h. Phone check (plan 1f)

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

## i. Exit criterion (plan 1g)

Merge any trivial commit to `master`, then on the VPS:

```bash
cd /home/luka/notif
./deploy.sh --apk
```

Expect `=== Deploy complete ===` followed by the publish lines from step e. On the phone,
refresh F-Droid once: Notif must show an update. Install it and open the app.

## Refusals and what they mean

| Message | Meaning | Action |
|---|---|---|
| `refused: pin missing: ...` | step c is not done, or the pin file was edited | finish step c |
| `REFUSED: repo index key cert SHA-256 ... does not match the pin` | `/etc/notif/fdroid/repo-index.p12` is not the pinned key | stop; restore from the backup |
| `REFUSED: check 3a: ...` | debug-signed, signed with another key, or more than one signer | stop; the APK key or the build is wrong |
| `REFUSED: check 3b: ...` | built without the production `API_URL` | rebuild with `notif-apk build` |
| `check 3c: versionCode N is already published; nothing to do` | same commit published before (exit 0) | none |
| `REFUSED: check 3c: ... lower than the newest published` | an older commit, or `master` was rewritten | build a newer commit; never force-push `master` |
| `REFUSED: check 3d: ... already exists in repo/` | a stray APK not in the index, left by an interrupted publish | report; remove only after confirming it is not in `index-v2.json` |
| `another notif-apk run is in progress` | another build or publish holds the lock | wait for it |
| `REFUSED: fdroid update failed; removed ...` | indexing failed; the new APK was removed again | report the `fdroid` output above it |

To reset the build caches (for example after a Flutter upgrade):
`docker volume rm notif-apk-gradle notif-apk-pub`.
