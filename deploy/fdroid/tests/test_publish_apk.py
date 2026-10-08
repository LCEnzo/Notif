import hashlib
import json
import os
import stat
import tempfile
import zipfile
from pathlib import Path

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

import publish_apk
from tests.conftest import run_tool, shell_tool

CERT = "3f" * 32
PUBKEY = "9e" * 32


def apksigner_output(*signers: str, count: int | None = None) -> str:
	lines = [
		"Verifies",
		"Verified using v1 scheme (JAR signing): true",
		"Verified using v2 scheme (APK Signature Scheme v2): true",
		"Verified using v3 scheme (APK Signature Scheme v3): true",
		"Verified using v4 scheme (APK Signature Scheme v4): false",
		f"Number of signers: {len(signers) if count is None else count}",
	]
	for n, cert in enumerate(signers, start=1):
		lines += [
			f"Signer #{n} certificate DN: CN=Notif APK",
			f"Signer #{n} certificate SHA-256 digest: {cert}",
			f"Signer #{n} certificate SHA-1 digest: {cert[:40]}",
			f"Signer #{n} key algorithm: RSA",
			f"Signer #{n} public key SHA-256 digest: {PUBKEY}",
		]
	return "\n".join(lines) + "\n"


def test_single_signer_is_the_certificate_digest_not_the_public_key():
	assert publish_apk.single_signer(apksigner_output(CERT)) == CERT


@pytest.mark.parametrize(
	"output",
	[
		apksigner_output(CERT, "4e" * 32),  # two signers
		apksigner_output(CERT, count=2),  # one digest line, but two signers reported
		apksigner_output(),  # none
		apksigner_output(CERT).replace("Number of signers: 1\n", ""),
		apksigner_output(CERT.upper()),  # not a lowercase digest
		apksigner_output(CERT).replace(f"digest: {CERT}", f"digest: {CERT} "),
		apksigner_output(CERT).replace("Number of signers: 1", "Number of signers: 1 "),
	],
)
def test_anything_but_exactly_one_signer_is_rejected(output):
	assert publish_apk.single_signer(output) is None


URL = publish_apk.API_URL.encode()


@pytest.mark.parametrize(
	("libapp", "problem"),
	[
		(b"\0" + URL + b"\0", None),
		(b"\0" + URL[:-1] + b"\0", "does not contain"),  # a prefix of the URL is not the URL
		(b"\0http://localhost:8000/api/v1\0", "does not contain"),
		(b"\0" + URL + b"\0localhost:8000\0", "contains localhost:8000"),
	],
)
def test_libapp_check(libapp, problem):
	result = publish_apk.libapp_problem(libapp)
	assert (result is None) if problem is None else (result is not None and problem in result)


def write_apk(path: Path, members: dict[str, bytes]) -> Path:
	with zipfile.ZipFile(path, "w") as z:
		for name, data in members.items():
			z.writestr(name, data)
	return path


def test_read_libapp(tmp_path: Path):
	apk = write_apk(tmp_path / "a.apk", {"AndroidManifest.xml": b"m", publish_apk.LIBAPP: b"lib" + URL})
	assert publish_apk.read_libapp(apk) == b"lib" + URL


@pytest.mark.parametrize(
	"members",
	[{"AndroidManifest.xml": b"m"}, {publish_apk.LIBAPP: b""}, {"lib/armeabi-v7a/libapp.so": b"lib"}],
)
def test_missing_or_empty_libapp_is_refused(tmp_path: Path, members):
	apk = write_apk(tmp_path / "a.apk", members)
	with pytest.raises(publish_apk.RefusedError, match=r"check 3b: lib/arm64-v8a/libapp.so missing from the APK"):
		publish_apk.read_libapp(apk)


def test_a_file_that_is_not_a_zip_has_no_libapp(tmp_path: Path):
	apk = tmp_path / "a.apk"
	apk.write_bytes(b"not a zip")
	with pytest.raises(publish_apk.RefusedError, match="missing from the APK"):
		publish_apk.read_libapp(apk)


@pytest.mark.parametrize(("value", "expected"), [(1, 1), (674, 674), ("5", 5), ("2100000000", 2100000000)])
def test_version_codes(value, expected):
	assert publish_apk.parse_version_code(value) == expected


@pytest.mark.parametrize("value", [0, -1, True, None, "05", "0", "", "5 ", 5.0, "0x10"])
def test_bad_version_codes(value):
	with pytest.raises(ValueError, match="^not a positive integer: "):
		publish_apk.parse_version_code(value)


def index_with(codes: list[int], app_id: str = publish_apk.APP_ID) -> dict[str, object]:
	versions = {f"sha{n}": {"manifest": {"versionCode": code}} for n, code in enumerate(codes)}
	return {"repo": {}, "packages": {app_id: {"versions": versions}, "other.app": {"versions": {}}}}


@given(st.lists(st.integers(min_value=1, max_value=2**31), max_size=6))
def test_newest_version_code_is_the_maximum(codes):
	assert publish_apk.newest_version_code(index_with(codes), publish_apk.APP_ID) == max(codes, default=0)


def test_newest_version_code_of_an_empty_or_other_index_is_0():
	assert publish_apk.newest_version_code({}, publish_apk.APP_ID) == 0
	assert publish_apk.newest_version_code({"packages": {}}, publish_apk.APP_ID) == 0
	assert publish_apk.newest_version_code(index_with([9], "other.id"), publish_apk.APP_ID) == 0


@pytest.mark.parametrize(
	"index",
	[
		[],
		{"packages": []},
		{"packages": {publish_apk.APP_ID: {"versions": [1]}}},
		{"packages": {publish_apk.APP_ID: {"versions": {"x": {}}}}},
		{"packages": {publish_apk.APP_ID: {"versions": {"x": {"manifest": {"versionCode": "5"}}}}}},
		{"packages": {publish_apk.APP_ID: {"versions": {"x": {"manifest": {"versionCode": True}}}}}},
	],
)
def test_unexpected_index_shapes_are_errors(index):
	with pytest.raises(ValueError, match=" is not an object$|^versionCode "):
		publish_apk.newest_version_code(index, publish_apk.APP_ID)


@pytest.mark.parametrize(
	("code", "newest", "verdict"),
	[(673, 674, "LOWER"), (674, 674, "PUBLISHED"), (675, 674, "NEWER"), (1, 0, "NEWER")],
)
def test_version_verdict_boundaries(code, newest, verdict):
	assert publish_apk.version_verdict(code, newest) is publish_apk.Verdict[verdict]


def apk(code: int | str) -> str:
	return f"com.lcenzo.notif_{code}.apk"


def test_prune_keeps_the_newest_three_counting_the_new_one():
	names = [apk(672), apk(1001), apk(1002), "index-v2.json", "entry.jar"]
	assert publish_apk.prune_selection(names, apk(1003), 3) == [apk(672)]
	assert publish_apk.prune_selection(names[1:], apk(1003), 3) == []


@pytest.mark.parametrize(
	"name",
	[
		"comXlcenzoXnotif_5.apk",  # the dots are literal
		"com.lcenzo.notif_5.apk.bak",
		"com.lcenzo.notif_5.APK",
		"com.lcenzo.notif_.apk",
		"com.lcenzo.notif_-5.apk",
		"x.com.lcenzo.notif_5.apk",
		"org.example_1.apk",
	],
)
def test_only_names_publish_writes_are_pruned(name):
	assert publish_apk.prune_selection([name, apk(1), apk(2), apk(3)], apk(4), 3) == [apk(1)]


SED = shell_tool("sed")
SORT = shell_tool("sort")
NAMES = st.lists(
	st.one_of(
		st.integers(min_value=0, max_value=10**12).map(apk),
		st.sampled_from(["007", "7", "0", "00", "10", "99999999999999999999"]).map(apk),
		st.sampled_from(
			["comXlcenzoXnotif_3.apk", "com.lcenzo.notif_3.apk.part", "index.jar", "com.lcenzo.notif_x.apk"]
		),
	),
	unique=True,
	max_size=8,
)


@pytest.mark.skipif(SED is None or SORT is None, reason="needs POSIX sed and sort")
@settings(max_examples=300, deadline=None)
@given(names=NAMES, new=st.integers(min_value=1, max_value=10**12), keep=st.integers(min_value=0, max_value=4))
def test_prune_selection_matches_the_shell_pipeline(names, new, keep):
	assert SED is not None
	assert SORT is not None
	new_name = apk(new)
	names = [n for n in names if n != new_name]
	listing = "".join(f"{n}\n" for n in [*names, new_name]).encode()
	codes = run_tool([SED, "-nE", r"s/^com\.lcenzo\.notif_([0-9]+)\.apk$/\1/p"], listing)
	ordered = run_tool([SORT, "-rn"], codes).decode().splitlines()
	assert publish_apk.prune_selection(names, new_name, keep) == [apk(c) for c in ordered[keep:]]


# --- add_to_repo and rollback, with real rsync and a fake fdroid ---

FAKE_FDROID = """#!/bin/sh
case $FAKE_FDROID in
  early) exit 1 ;;
  late)
    printf '{"rewritten": true}' >repo/index-v2.json
    rm repo/entry.jar
    mkdir -p repo/status && printf '{}' >repo/status/new.json
    exit 1 ;;
  ok) printf '{"published": true}' >repo/index-v2.json ;;
esac
"""


def fingerprint(root: Path) -> list[tuple[object, ...]]:
	"""Every entry under <root>: kind, mode, mtime, and for files size and SHA-256."""
	entries: list[tuple[object, ...]] = []
	for path in [root, *root.rglob("*")]:
		st_ = path.lstat()
		rel = path.relative_to(root).as_posix()
		if stat.S_ISDIR(st_.st_mode):
			entries.append(("dir", rel, st_.st_mode, st_.st_mtime_ns))
		else:
			digest = hashlib.sha256(path.read_bytes()).hexdigest()
			entries.append(("file", rel, st_.st_mode, st_.st_mtime_ns, st_.st_size, digest))
	return sorted(entries, key=lambda e: str(e[1]))


@pytest.fixture
def repo(tmp_path: Path, monkeypatch):
	if shell_tool("rsync") is None:
		pytest.skip("needs rsync")
	work = tmp_path / "work"
	repo = work / "repo"
	(repo / "icons").mkdir(parents=True)
	for code in (2001, 2002, 2003):
		(repo / apk(code)).write_bytes(f"apk {code}".encode())
	(repo / "index-v2.json").write_text(json.dumps(index_with([2001, 2002, 2003])), encoding="utf-8")
	(repo / "entry.jar").write_bytes(b"jar")
	(repo / "icons" / "icon.png").write_bytes(b"png")
	# Aged like a served repo/: rsync (3.5.0) does not carry over a directory
	# mtime from the current second, so a fresh root would differ after restore.
	for path in [*repo.rglob("*"), repo]:
		os.utime(path, ns=(1_700_000_000_123_456_789, 1_700_000_000_123_456_789))
	bin_dir = tmp_path / "bin"
	bin_dir.mkdir()
	fdroid = bin_dir / "fdroid"
	fdroid.write_text(FAKE_FDROID, encoding="utf-8")
	fdroid.chmod(0o755)
	monkeypatch.setattr(publish_apk, "WORK", work)
	monkeypatch.setattr(publish_apk, "REPO", repo)
	new = tmp_path / "new.apk"
	new.write_bytes(b"apk 2004")
	return {"repo": repo, "new": new, "path": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}


def add(repo, mode: str):
	journal = publish_apk.Journal()
	env = {**os.environ, "PATH": repo["path"], "FAKE_FDROID": mode}
	target = repo["repo"] / apk(2004)
	prune = publish_apk.prune_selection([p.name for p in repo["repo"].iterdir()], target.name, publish_apk.KEEP)
	with tempfile.TemporaryDirectory() as scratch:
		try:
			publish_apk.add_to_repo(repo["new"], target, prune, Path(scratch), env, journal)
		except (publish_apk.PublishError, OSError) as e:
			return journal, e
	return journal, None


@pytest.mark.parametrize("mode", ["early", "late"])
def test_a_failed_fdroid_update_restores_repo_exactly(repo, mode):
	before = fingerprint(repo["repo"])
	journal, error = add(repo, mode)
	assert isinstance(error, publish_apk.PublishError)
	assert journal.pruned == [apk(2001)]
	assert journal.restored is True
	assert fingerprint(repo["repo"]) == before


def test_a_restore_in_the_same_second_still_restores_every_file(repo):
	# The other side of the fixture's ageing: with repo/ changed this second,
	# rsync leaves directory mtimes as they are, but every file comes back exactly.
	os.utime(repo["repo"])
	before = [e for e in fingerprint(repo["repo"]) if e[0] == "file"]
	_, error = add(repo, "late")
	assert isinstance(error, publish_apk.PublishError)
	assert [e for e in fingerprint(repo["repo"]) if e[0] == "file"] == before


def test_a_successful_update_prunes_and_publishes(repo):
	journal, error = add(repo, "ok")
	assert error is None
	assert journal.pruned == [apk(2001)]
	names = sorted(p.name for p in repo["repo"].iterdir() if p.suffix == ".apk")
	assert names == [apk(2002), apk(2003), apk(2004)]
	assert (repo["repo"] / apk(2004)).read_bytes() == b"apk 2004"
	assert stat.S_IMODE((repo["repo"] / apk(2004)).stat().st_mode) == 0o644


def test_an_apk_that_appeared_meanwhile_is_neither_replaced_nor_removed(repo):
	(repo["repo"] / apk(2004)).write_bytes(b"someone else's")
	before = fingerprint(repo["repo"])
	journal, error = add(repo, "ok")
	assert isinstance(error, FileExistsError)
	assert journal.created is False
	assert journal.restored is True
	assert fingerprint(repo["repo"]) == before


@pytest.mark.parametrize(
	("environ", "message"),
	[
		({}, "pin missing: APK cert SHA-256 (deploy/fdroid/pins/apk-cert.sha256)"),
		({"APK_CERT_SHA256": CERT.upper()}, "pin missing: APK cert SHA-256 (deploy/fdroid/pins/apk-cert.sha256)"),
		({"APK_CERT_SHA256": CERT}, "pin missing: repo index cert SHA-256 (deploy/fdroid/pins/repo-index-cert.sha256)"),
	],
)
def test_main_refuses_without_pins(tmp_path: Path, monkeypatch, capsys, environ, message):
	monkeypatch.setattr(publish_apk, "REPO", tmp_path)
	assert publish_apk.main(["publish_apk.py", __file__], environ) == 1
	assert capsys.readouterr().err == f"publish: REFUSED: {message}\n"


def test_main_refuses_an_unmounted_repo(tmp_path: Path, monkeypatch, capsys):
	monkeypatch.setattr(publish_apk, "REPO", tmp_path / "repo")
	assert publish_apk.main(["publish_apk.py", __file__], {}) == 1
	assert capsys.readouterr().err == f"publish: REFUSED: repo directory {tmp_path / 'repo'} is not mounted\n"


def test_main_usage(capsys):
	assert publish_apk.main(["publish_apk.py"], {}) == 1
	assert capsys.readouterr().err == "publish: REFUSED: usage: publish_apk.py <apk>\n"
