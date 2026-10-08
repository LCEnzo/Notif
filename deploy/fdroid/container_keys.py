"""Signing key operations inside the notif-apk publish image, for `notif-apk
setup` and `notif-apk export-keys`. The key directory is mounted at /keys.

  inspect         print "absent", "partial <files present>", or
                  "present <APK cert SHA-256> <repo index cert SHA-256>"
  generate        create both keys; refuses if any key file exists
  restore <tar>   install the keys from a backup tar; if APK_CERT_SHA256
                  and REPO_CERT_SHA256 are set, only when they match
  archive         write a backup tar (fdroid/<file>) to stdout

Run as `python3 /tool/container_keys.py <command>`. Passwords stay in their
files: keytool reads them with -storepass:file.
"""

import base64
import hashlib
import lzma
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import zlib
from collections.abc import Iterator, Mapping, Sequence
from contextlib import contextmanager
from pathlib import Path
from types import FrameType
from typing import BinaryIO, NoReturn

KEYS = Path("/keys")
FILES = ("apk.p12", "apk.pass", "repo-index.p12", "repo-index.pass")
HEX64 = re.compile(r"[0-9a-f]{64}")
# A keystore is a few KB. These bound what a damaged or foreign tar can make restore read.
MAX_MEMBER_BYTES = 1 << 20
MAX_MEMBERS = 1000


class FatalError(Exception):
	"""Ends with `notif-apk keys: <message>` on stderr and exit 1."""


class BackupError(Exception):
	pass


def fail(message: str) -> NoReturn:
	raise FatalError(message)


def is_regular(path: Path) -> bool:
	"""A regular file, not a symlink to one."""
	try:
		return stat.S_ISREG(path.lstat().st_mode)
	except OSError:
		return False


def cert_sha256(directory: Path, name: str, alias: str) -> str | None:
	"""SHA-256 of the DER certificate of <directory>/<name>.p12, or None if keytool cannot read it."""
	argv = [
		"keytool", "-exportcert",
		"-keystore", str(directory / f"{name}.p12"),
		"-alias", alias,
		"-storepass:file", str(directory / f"{name}.pass"),
	]  # fmt: skip
	try:
		result = subprocess.run(argv, stdout=subprocess.PIPE, check=False)
	except FileNotFoundError:
		fail("keytool not found")
	if result.returncode != 0:
		# keytool reports its errors on stdout, which would otherwise be the certificate.
		sys.stderr.write(result.stdout.decode("utf-8", "replace"))
		return None
	return hashlib.sha256(result.stdout).hexdigest()


def present_files(keys: Path) -> list[str]:
	return [f for f in FILES if (keys / f).exists(follow_symlinks=False)]


def digests(directory: Path) -> tuple[str, str]:
	"""The APK and repo index cert SHA-256s of the key set in <directory>."""
	for f in FILES:
		if not is_regular(directory / f):
			fail(f"{f} is not a regular file")
	apk = cert_sha256(directory, "apk", "notif-apk") or fail("cannot read apk.p12 with apk.pass")
	repo = cert_sha256(directory, "repo-index", "notif-repo") or fail("cannot read repo-index.p12 with repo-index.pass")
	return apk, repo


def inspect(keys: Path) -> str:
	present = present_files(keys)
	if not present:
		return "absent"
	if len(present) < len(FILES):
		return "partial " + " ".join(present)
	apk, repo = digests(keys)
	return f"present {apk} {repo}"


def refuse_if_any_present(keys: Path) -> None:
	present = present_files(keys)
	if present:
		fail(f"refusing: the key directory already holds {' '.join(present)}")


def remove(path: Path) -> None:
	if path.is_dir() and not path.is_symlink():
		shutil.rmtree(path)
	else:
		path.unlink(missing_ok=True)


@contextmanager
def staging(keys: Path) -> Iterator[Path]:
	"""An empty <keys>/.staging, removed afterwards; same filesystem, so install_from can hard-link."""
	stage = keys / ".staging"
	remove(stage)
	stage.mkdir(mode=0o700)
	stage.chmod(0o700)
	try:
		yield stage
	finally:
		remove(stage)


def install_from(directory: Path, keys: Path) -> None:
	"""Hard links, because a link never replaces an existing file."""
	for f in FILES:
		(directory / f).chmod(0o600)
	for f in FILES:
		try:
			os.link(directory / f, keys / f)
		except OSError as e:
			fail(f"cannot install {f}: {e.strerror}")


def generate(keys: Path) -> None:
	refuse_if_any_present(keys)
	os.umask(0o077)
	with staging(keys) as stage:
		for name, alias, dname in (
			("apk", "notif-apk", "CN=Notif APK"),
			("repo-index", "notif-repo", "CN=notif-repo, OU=F-Droid"),
		):
			password = stage / f"{name}.pass"
			with password.open("xb") as f:
				f.write(base64.b64encode(secrets.token_bytes(32)))
			argv = [
				"keytool", "-genkeypair",
				"-keystore", str(stage / f"{name}.p12"), "-storetype", "pkcs12", "-alias", alias,
				"-keyalg", "RSA", "-keysize", "4096", "-sigalg", "SHA256withRSA", "-validity", "10000",
				"-dname", dname, "-storepass:file", str(password), "-keypass:file", str(password),
			]  # fmt: skip
			try:
				status = subprocess.run(argv, check=False).returncode
			except FileNotFoundError:
				fail("keytool not found")
			if status != 0:
				fail(f"keytool could not generate {name}.p12 (see above)")
		install_from(stage, keys)


def extract_keys(tar: Path, dest: Path) -> None:
	"""Writes the four fdroid/<file> members of <tar> into <dest>. Nothing else is
	extracted, and only regular members count. Raises BackupError."""
	wanted = {f"fdroid/{f}": f for f in FILES}
	try:
		with tarfile.open(tar) as archive:
			found: dict[str, tarfile.TarInfo] = {}
			for count, member in enumerate(archive, start=1):
				if count > MAX_MEMBERS:
					raise BackupError(f"more than {MAX_MEMBERS} members")
				if member.name in wanted:
					found[member.name] = member  # the last one wins, as with tar -x
			missing = [name for name in wanted if name not in found]
			if missing:
				raise BackupError(f"missing {', '.join(missing)}")
			for name, member in found.items():
				if not member.isreg():
					raise BackupError(f"{name} is not a regular file")
				if member.size > MAX_MEMBER_BYTES:
					raise BackupError(f"{name} is larger than {MAX_MEMBER_BYTES} bytes")
				source = archive.extractfile(member)
				if source is None:
					raise BackupError(f"cannot read {name}")
				with source, (dest / wanted[name]).open("xb") as out:
					shutil.copyfileobj(source, out)
	except (tarfile.TarError, OSError, EOFError, zlib.error, lzma.LZMAError) as e:
		raise BackupError(str(e)) from e


def restore(tar: Path, keys: Path, environ: Mapping[str, str]) -> None:
	apk_pin = environ.get("APK_CERT_SHA256", "")
	repo_pin = environ.get("REPO_CERT_SHA256", "")
	if not tar.is_file():
		fail(f"not a file: {tar}")
	if (apk_pin or repo_pin) and not (HEX64.fullmatch(apk_pin) and HEX64.fullmatch(repo_pin)):
		fail("set both pins or neither")
	refuse_if_any_present(keys)
	os.umask(0o077)
	with staging(keys) as stage:
		backup = stage / "fdroid"
		backup.mkdir()
		try:
			extract_keys(tar, backup)
		except BackupError as e:
			fail(
				"the backup does not hold fdroid/{apk.p12,apk.pass,repo-index.p12,repo-index.pass};"
				f" installed nothing ({e})"
			)
		apk, repo = digests(backup)
		if apk_pin:
			if apk != apk_pin:
				fail(f"the backup's APK cert SHA-256 is {apk}, the pin is {apk_pin}; installed nothing")
			if repo != repo_pin:
				fail(f"the backup's repo index cert SHA-256 is {repo}, the pin is {repo_pin}; installed nothing")
		install_from(backup, keys)


def archive(keys: Path, out: BinaryIO) -> None:
	for f in FILES:
		if not is_regular(keys / f):
			fail(f"{f} is not a regular file")
	with tarfile.open(fileobj=out, mode="w|", format=tarfile.GNU_FORMAT) as tar:
		for f in FILES:
			path = keys / f
			member = tar.gettarinfo(str(path), arcname=f"fdroid/{f}")
			member.mtime = int(member.mtime)
			with path.open("rb") as source:
				tar.addfile(member, source)
	out.flush()


def main(argv: Sequence[str], environ: Mapping[str, str]) -> int:
	try:
		match argv[1:]:
			case ["inspect"]:
				print(inspect(KEYS))
			case ["generate"]:
				generate(KEYS)
			case ["archive"]:
				archive(KEYS, sys.stdout.buffer)
			case ["restore", tar]:
				restore(Path(tar), KEYS, environ)
			case [("inspect" | "generate" | "archive") as command, *_]:
				fail(f"usage: container_keys.py {command}")
			case ["restore", *_]:
				fail("usage: container_keys.py restore <tar>")
			case _:
				fail("usage: container_keys.py inspect | generate | restore <tar> | archive")
	except FatalError as e:
		print(f"notif-apk keys: {e}", file=sys.stderr)
		return 1
	return 0


def _ignore(_signum: int, _frame: FrameType | None) -> None:
	pass


if __name__ == "__main__":
	# PID 1 in its container, and docker forwards Ctrl-C to it. Ignored, so a
	# key operation never stops halfway. A handler, not SIG_IGN, so keytool keeps
	# the default disposition.
	signal.signal(signal.SIGINT, _ignore)
	sys.exit(main(sys.argv, os.environ))
