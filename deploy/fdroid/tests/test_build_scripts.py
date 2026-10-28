"""build-apk.sh and sign-apk.sh against fake flutter and apksigner, on Linux."""

import os
import secrets
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

from tests.conftest import FDROID_DIR, shell_tool

BASH = shell_tool("bash")
pytestmark = pytest.mark.skipif(BASH is None, reason="needs POSIX bash")

FAKE_FLUTTER = """#!/bin/sh
{ printf 'argv: %s\\n' "$*"; env; } >>"$FAKE_LOG"
if [ "$1" = build ]; then
  mkdir -p build/app/outputs/flutter-apk
  printf 'debug-signed release' >build/app/outputs/flutter-apk/app-release.apk
fi
"""

FAKE_APKSIGNER = """#!/bin/sh
{ printf 'argv: %s\\n' "$*"; env; } >>"$FAKE_LOG"
if [ "$1" = sign ]; then
  while [ $# -gt 0 ]; do
    case $1 in
      --out) out=$2 ;;
      --ks-pass) cat "${2#file:}" >"$FAKE_PASS_READ" ;;
    esac
    shift
  done
  printf 'signed' >"$out"
fi
if [ "$1" = verify ]; then
  echo 'WARNING: a fake verify warning' >&2
  [ "${FAKE_VERIFY_STATUS:-0}" = 0 ] || echo 'ERROR: a fake verify error'
  exit "${FAKE_VERIFY_STATUS:-0}"
fi
"""


def executable(path: Path, text: str) -> Path:
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(text, encoding="utf-8")
	path.chmod(0o755)
	return path


def run_script(name: str, args: list[str], cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[bytes]:
	assert BASH is not None
	return subprocess.run([BASH, str(FDROID_DIR / name), *args], cwd=cwd, env=env, capture_output=True, check=False)


def test_build_apk_builds_without_a_key(tmp_path: Path):
	repo = tmp_path / "repo"
	(repo / "frontend").mkdir(parents=True)
	(repo / "frontend" / "pubspec.yaml").write_text("name: notif\n", encoding="utf-8")
	executable(tmp_path / "bin" / "flutter", FAKE_FLUTTER)
	log = tmp_path / "log"
	env = {"PATH": f"{tmp_path / 'bin'}{os.pathsep}{os.defpath}", "FAKE_LOG": str(log)}
	assert run_script("build-apk.sh", ["674", "c0ffeec"], repo, env).returncode == 0
	assert (repo / "out" / "notif-674-c0ffeec-debug-signed.apk").read_bytes() == b"debug-signed release"
	assert "argv: build apk --release" in log.read_text(encoding="utf-8")


@dataclass
class Signing:
	root: Path
	password: str
	keystore: Path
	pass_file: Path
	debug_signed: Path
	signed: Path
	log: Path
	env: dict[str, str]

	def run(self) -> subprocess.CompletedProcess[bytes]:
		return run_script("sign-apk.sh", [str(self.debug_signed), str(self.signed)], self.root, self.env)


@pytest.fixture
def signing(tmp_path: Path) -> Signing:
	password = secrets.token_urlsafe(24)
	keystore = tmp_path / "secrets" / "apk.p12"
	keystore.parent.mkdir()
	keystore.write_bytes(b"keystore")
	pass_file = tmp_path / "secrets" / "apk.pass"
	pass_file.write_text(password, encoding="utf-8")
	sdk = tmp_path / "sdk"
	executable(sdk / "build-tools" / "36.0.0" / "apksigner", FAKE_APKSIGNER)
	debug_signed = tmp_path / "in.apk"
	debug_signed.write_bytes(b"debug-signed release")
	signed = tmp_path / "out" / "notif.apk"
	signed.parent.mkdir()
	log = tmp_path / "log"
	env = {
		"PATH": os.defpath,
		"ANDROID_HOME": str(sdk),
		"APK_KS": str(keystore),
		"APK_KS_PASS_FILE": str(pass_file),
		"FAKE_LOG": str(log),
		"FAKE_PASS_READ": str(tmp_path / "pass-read"),
	}
	return Signing(tmp_path, password, keystore, pass_file, debug_signed, signed, log, env)


def test_sign_apk_reads_the_password_only_from_its_file(signing: Signing):
	assert signing.run().returncode == 0
	assert signing.signed.read_bytes() == b"signed"
	assert (signing.root / "pass-read").read_text(encoding="utf-8") == signing.password
	log = signing.log.read_text(encoding="utf-8")
	calls = [line for line in log.splitlines() if line.startswith("argv: ")]
	assert [call.split()[1] for call in calls] == ["sign", "verify"]
	assert f"--ks {signing.keystore} --ks-key-alias notif-apk --ks-pass file:{signing.pass_file}" in calls[0]
	assert calls[1] == f"argv: verify {signing.signed}"
	assert signing.password not in log


def test_sign_apk_prints_only_its_own_line_when_verify_passes(signing: Signing):
	result = signing.run()
	assert result.returncode == 0
	assert result.stdout.decode() == f"sign-apk: signed {signing.signed}\n"
	assert result.stderr.decode() == ""


def test_sign_apk_fails_with_apksigners_output_when_verify_fails(signing: Signing):
	signing.env["FAKE_VERIFY_STATUS"] = "1"
	result = signing.run()
	assert result.returncode == 1
	assert result.stdout.decode() == ""
	assert "ERROR: a fake verify error" in result.stderr.decode()
	assert "WARNING: a fake verify warning" in result.stderr.decode()
