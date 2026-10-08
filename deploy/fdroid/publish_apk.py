"""Verify a signed Notif APK and add it to the F-Droid repo (plan checks 3a-3d).

Runs inside the notif-apk publish image as `python3 /tool/publish_apk.py <apk>`;
`notif-apk publish` sets up:
  /tool                          deploy/fdroid (read-only)
  /work/repo                     the served repo directory
  /run/secrets/repo-index.p12    index keystore and its password file (read-only)
  /run/secrets/repo-index.pass
  APK_CERT_SHA256, REPO_CERT_SHA256   pinned cert digests from deploy/fdroid/pins

Exit 0: published, or versionCode already published (no-op). Exit 1: refused, or
publishing failed and repo/ was restored to its state before the run.
"""

import hashlib
import io
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import zipfile
import zlib
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from types import FrameType
from typing import NoReturn

APP_ID = "com.lcenzo.notif"
API_URL = "https://notif.lcenzo.com/api/v1"
DEV_API_HOST = "localhost:8000"
REPO_KEY_ALIAS = "notif-repo"
KEEP = 3
TOOL = Path("/tool")
WORK = Path("/work")
REPO = WORK / "repo"
SECRETS = Path("/run/secrets")
LIBAPP = "lib/arm64-v8a/libapp.so"
# Dart AOT output is tens of MB; the cap bounds what one zip entry can make us hold in memory.
MAX_LIBAPP_BYTES = 256 << 20
HEX64 = re.compile(r"[0-9a-f]{64}")
SIGNER_LINE = re.compile(r"Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-f]{64})")
APK_NAME = re.compile(rf"{re.escape(APP_ID)}_([0-9]+)\.apk")
VERSION_CODE = re.compile(r"[1-9][0-9]*")


class RefusedError(Exception):
	"""Ends with `publish: REFUSED: <message>` on stderr and exit 1."""


class PublishError(Exception):
	"""`fdroid update` failed."""


def refuse(message: str) -> NoReturn:
	raise RefusedError(message)


def info(message: str) -> None:
	print(f"publish: {message}")


def run(
	argv: Sequence[str],
	*,
	cwd: Path | None = None,
	env: Mapping[str, str] | None = None,
	stdout: int | None = None,
	stderr: int | None = None,
) -> subprocess.CompletedProcess[bytes]:
	try:
		return subprocess.run(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr, check=False)
	except FileNotFoundError:
		print(f"publish: {argv[0]}: command not found", file=sys.stderr)
		return subprocess.CompletedProcess(argv, 127, b"", b"")


def single_signer(apksigner_output: str) -> str | None:
	"""The cert SHA-256 of the one signer `apksigner verify --print-certs` reports,
	or None unless it reports exactly one."""
	lines = apksigner_output.split("\n")
	digests = [m.group(1) for line in lines if (m := SIGNER_LINE.fullmatch(line))]
	if len(digests) != 1 or "Number of signers: 1" not in lines:
		return None
	return digests[0]


def libapp_problem(libapp: bytes) -> str | None:
	"""Why check 3b refuses this libapp.so, or None if it passes."""
	if API_URL.encode() not in libapp:
		return f"check 3b: libapp.so does not contain {API_URL}"
	if DEV_API_HOST.encode() in libapp:
		return f"check 3b: libapp.so contains {DEV_API_HOST}"
	return None


def parse_version_code(value: object) -> int:
	"""A versionCode as fdroidserver reports it; raises ValueError unless it is a positive integer."""
	if isinstance(value, int) and not isinstance(value, bool) and value >= 1:
		return value
	if isinstance(value, str) and VERSION_CODE.fullmatch(value):
		return int(value)
	raise ValueError(f"not a positive integer: {value!r}")


def newest_version_code(index: object, app_id: str) -> int:
	"""The highest versionCode of <app_id> in a parsed index-v2.json, 0 if none.
	Raises ValueError if the index does not have the expected shape."""
	if not isinstance(index, dict):
		raise ValueError("index is not an object")
	packages = index.get("packages", {})
	if not isinstance(packages, dict):
		raise ValueError("packages is not an object")
	package = packages.get(app_id, {})
	if not isinstance(package, dict):
		raise ValueError(f"{app_id} is not an object")
	versions = package.get("versions", {})
	if not isinstance(versions, dict):
		raise ValueError("versions is not an object")
	codes: list[int] = []
	for version in versions.values():
		manifest = version.get("manifest") if isinstance(version, dict) else None
		code = manifest.get("versionCode") if isinstance(manifest, dict) else None
		if not isinstance(code, int) or isinstance(code, bool):
			raise ValueError(f"versionCode {code!r}")
		codes.append(code)
	return max(codes, default=0)


class Verdict(Enum):
	NEWER = "newer"
	PUBLISHED = "already published"
	LOWER = "lower"


def version_verdict(version_code: int, newest: int) -> Verdict:
	if version_code == newest:
		return Verdict.PUBLISHED
	return Verdict.NEWER if version_code > newest else Verdict.LOWER


def prune_selection(names: Iterable[str], new_name: str, keep: int) -> list[str]:
	"""The APKs to prune so that the newest <keep>, counting <new_name>, remain.
	Only names this script writes are candidates."""
	codes = [m.group(1) for name in [*names, new_name] if (m := APK_NAME.fullmatch(name))]
	# Numeric, newest first; ties (leading zeros) in reverse byte order, like sort -rn.
	codes.sort(key=lambda code: (int(code), code), reverse=True)
	return [f"{APP_ID}_{code}.apk" for code in codes[keep:]]


def read_password(path: Path) -> str:
	try:
		return path.read_text(encoding="utf-8").rstrip("\n")
	except (OSError, UnicodeDecodeError) as e:
		refuse(f"cannot read {path}: {e}")


def check_index_key(env: Mapping[str, str], pin: str) -> None:
	result = run(
		[
			"keytool", "-exportcert",
			"-keystore", str(SECRETS / "repo-index.p12"),
			"-alias", REPO_KEY_ALIAS,
			"-storepass:env", "REPO_KS_PASS",
		],
		env=env,
		stdout=subprocess.PIPE,
	)  # fmt: skip
	if result.returncode != 0:
		# keytool reports its errors on stdout, which would otherwise be the certificate.
		sys.stderr.write(result.stdout.decode("utf-8", "replace"))
		refuse("cannot read the repo index key")
	cert = hashlib.sha256(result.stdout).hexdigest()
	if cert != pin:
		refuse(f"repo index key cert SHA-256 {cert} does not match the pin {pin}")


def check_signer(apk: Path, pin: str) -> None:
	"""Check 3a: signed by exactly one signer, the pinned APK key."""
	result = run(
		["apksigner", "verify", "--verbose", "--print-certs", str(apk)],
		stdout=subprocess.PIPE,
		stderr=subprocess.STDOUT,
	)
	output = result.stdout.decode("utf-8", "replace")
	if result.returncode != 0:
		print(output.rstrip("\n"), file=sys.stderr)
		refuse("check 3a: apksigner verify failed")
	signer = single_signer(output)
	if signer is None:
		print(output.rstrip("\n"), file=sys.stderr)
		refuse("check 3a: expected exactly one signer")
	if signer != pin:
		refuse(f"check 3a: signer cert SHA-256 {signer} does not match the pin {pin} (debug-signed or wrong key)")
	info("check 3a passed: signed by the pinned APK key")


def read_libapp(apk: Path) -> bytes:
	data = b""
	try:
		with zipfile.ZipFile(apk) as z:
			member = z.getinfo(LIBAPP)
			if member.file_size > MAX_LIBAPP_BYTES:
				refuse(f"check 3b: {LIBAPP} is larger than {MAX_LIBAPP_BYTES} bytes")
			data = z.read(member)
	except (KeyError, OSError, EOFError, zipfile.BadZipFile, zlib.error, NotImplementedError, RuntimeError):
		data = b""
	if not data:
		refuse(f"check 3b: {LIBAPP} missing from the APK")
	return data


def check_api_url(apk: Path) -> None:
	"""Check 3b: the production API URL is compiled in and the dev default is not."""
	problem = libapp_problem(read_libapp(apk))
	if problem is not None:
		refuse(problem)
	info(f"check 3b passed: built against {API_URL}")


def read_apk_id(apk: Path) -> tuple[object, object, object]:
	# Only the publish image has fdroidserver; importing here keeps the module importable by the unit tests.
	from fdroidserver import common  # noqa: PLC0415

	appid, version_code, version_name = common.get_apk_id(str(apk))
	return appid, version_code, version_name


def check_manifest(apk: Path) -> tuple[int, str]:
	"""The APK's versionCode and versionName, after checking its application ID."""
	try:
		appid, code, name = read_apk_id(apk)
	except Exception as e:  # noqa: BLE001 - androguard raises arbitrary exceptions on malformed APKs
		print(f"publish: {type(e).__name__}: {e}", file=sys.stderr)
		refuse("cannot read the APK manifest")
	if appid != APP_ID:
		refuse(f"APK is {appid}, expected {APP_ID}")
	try:
		version_code = parse_version_code(code)
	except ValueError:
		refuse(f"unexpected versionCode '{code}'")
	return version_code, str(name)


def newest_published() -> int:
	path = REPO / "index-v2.json"
	try:
		index: object = json.loads(path.read_text(encoding="utf-8"))
	except FileNotFoundError:
		index = {}
	except (OSError, ValueError):
		refuse(f"cannot read {path}")
	try:
		return newest_version_code(index, APP_ID)
	except ValueError:
		refuse(f"cannot read {path}")


def stage_config() -> None:
	"""fdroid update reads config.yml and metadata/ from its working directory."""
	metadata = WORK / "metadata"
	try:
		metadata.mkdir(mode=0o700, exist_ok=True)
		metadata.chmod(0o700)
		shutil.copyfile(TOOL / "config.yml", WORK / "config.yml")
		(WORK / "config.yml").chmod(0o600)
		shutil.copyfile(TOOL / "metadata" / f"{APP_ID}.yml", metadata / f"{APP_ID}.yml")
		(metadata / f"{APP_ID}.yml").chmod(0o644)
	except OSError as e:
		refuse(f"cannot stage the fdroid config: {e}")


def repo_apk_names() -> list[str]:
	"""Regular files in repo/; prune_selection picks the APKs among them."""
	with os.scandir(REPO) as entries:
		return [entry.name for entry in entries if entry.is_file(follow_symlinks=False)]


@dataclass
class Journal:
	"""What a publish changed in repo/, so that rollback undoes exactly that."""

	created: bool = False
	pruned: list[str] = field(default_factory=list)
	restored: bool = False


def apply(apk: Path, target: Path, prune: Sequence[str], held: Path, env: Mapping[str, str], journal: Journal) -> None:
	with target.open("xb") as out:  # never replaces an existing APK
		journal.created = True
		with apk.open("rb") as source:
			shutil.copyfileobj(source, out)
	target.chmod(0o644)
	for name in prune:
		shutil.move(REPO / name, held / name)
		journal.pruned.append(name)
	if run(["fdroid", "update"], cwd=WORK, env=env).returncode != 0:
		raise PublishError


def rollback(target: Path, held: Path, snapshot: Path, journal: Journal) -> bool:
	ok = True
	if journal.created:
		try:
			target.unlink(missing_ok=True)
		except OSError as e:
			print(f"publish: {e}", file=sys.stderr)
			ok = False
	for name in journal.pruned:
		try:
			shutil.move(held / name, REPO / name)
		except OSError as e:
			print(f"publish: {e}", file=sys.stderr)
			ok = False
	if run(["rsync", "-a", "--delete", "--exclude=/*.apk", f"{snapshot}/", f"{REPO}/"]).returncode != 0:
		ok = False
	return ok


def add_to_repo(
	apk: Path, target: Path, prune: Sequence[str], scratch: Path, env: Mapping[str, str], journal: Journal
) -> None:
	"""Installs <apk> as <target>, prunes, and runs fdroid update. If any of it
	fails, puts repo/ back as it was: the non-APK files from a snapshot (fdroid
	update can fail after rewriting the index), and the pruned APKs, which are
	moved aside instead of deleted until fdroid update has succeeded."""
	snapshot = scratch / "repo-before"
	held = scratch / "pruned"
	try:
		held.mkdir()
	except OSError as e:
		refuse(f"cannot snapshot repo/: {e}")
	if run(["rsync", "-a", "--exclude=/*.apk", f"{REPO}/", f"{snapshot}/"]).returncode != 0:
		refuse("cannot snapshot repo/")
	committed = False
	try:
		apply(apk, target, prune, held, env, journal)
		committed = True
	finally:
		if not committed:
			journal.restored = rollback(target, held, snapshot, journal)


def publish(args: Sequence[str], environ: Mapping[str, str]) -> None:
	if len(args) != 1:
		refuse("usage: publish_apk.py <apk>")
	apk = Path(args[0])
	if not apk.is_file():
		refuse(f"not a file: {apk}")
	if not REPO.is_dir():
		refuse(f"repo directory {REPO} is not mounted")
	apk_pin = environ.get("APK_CERT_SHA256", "")
	if not HEX64.fullmatch(apk_pin):
		refuse("pin missing: APK cert SHA-256 (deploy/fdroid/pins/apk-cert.sha256)")
	repo_pin = environ.get("REPO_CERT_SHA256", "")
	if not HEX64.fullmatch(repo_pin):
		refuse("pin missing: repo index cert SHA-256 (deploy/fdroid/pins/repo-index-cert.sha256)")

	# keytool and fdroid read the password from the environment, never from argv:
	# repo/status/*.json is public and records the fdroid command line.
	env = {**environ, "REPO_KS_PASS": read_password(SECRETS / "repo-index.pass")}
	check_index_key(env, repo_pin)
	check_signer(apk, apk_pin)
	check_api_url(apk)

	# 3c: versionCode above the newest in the published index; equal is a no-op.
	version_code, version_name = check_manifest(apk)
	newest = newest_published()
	match version_verdict(version_code, newest):
		case Verdict.PUBLISHED:
			info(f"check 3c: versionCode {version_code} is already published; nothing to do")
			return
		case Verdict.LOWER:
			refuse(f"check 3c: versionCode {version_code} is lower than the newest published, {newest}")
		case Verdict.NEWER:
			info(f"check 3c passed: versionCode {version_code} ({version_name}) > {newest}")

	# 3d: never overwrite an existing APK.
	target = REPO / f"{APP_ID}_{version_code}.apk"
	if target.exists(follow_symlinks=False):
		refuse(f"check 3d: {target.name} already exists in repo/")
	info(f"check 3d passed: {target.name} is new")

	stage_config()
	prune = prune_selection(repo_apk_names(), target.name, KEEP)
	journal = Journal()
	with tempfile.TemporaryDirectory() as scratch:
		try:
			add_to_repo(apk, target, prune, Path(scratch), env, journal)
		except (PublishError, OSError) as e:
			if isinstance(e, OSError):
				print(f"publish: {e}", file=sys.stderr)
			if not journal.restored:
				refuse("publish failed, and so did restoring repo/; it is now inconsistent (see the errors above)")
			refuse("publish failed (see the output above); restored repo/ to its state before this run")
	for name in journal.pruned:
		info(f"pruned {name}")
	info(f"published {target.name}")


def main(argv: Sequence[str], environ: Mapping[str, str]) -> int:
	try:
		publish(argv[1:], environ)
	except RefusedError as e:
		print(f"publish: REFUSED: {e}", file=sys.stderr)
		return 1
	return 0


def _ignore(_signum: int, _frame: FrameType | None) -> None:
	pass


if __name__ == "__main__":
	# Line-buffered, so these lines and fdroid's output stay in order.
	if isinstance(sys.stdout, io.TextIOWrapper):
		sys.stdout.reconfigure(line_buffering=True)
	# PID 1 in its container. The shell version had no INT handler there, so
	# Ctrl-C (which docker forwards) did not interrupt a publish halfway; Python's
	# default handler would. A handler, not SIG_IGN, so children keep the default.
	signal.signal(signal.SIGINT, _ignore)
	sys.exit(main(sys.argv, os.environ))
