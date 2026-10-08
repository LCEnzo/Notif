import gzip
import io
import tarfile
from pathlib import Path

import pytest

import container_keys

CONTENT = {f: f"secret {f}".encode() for f in container_keys.FILES}


def make_tar(path: Path, members: list[tarfile.TarInfo | tuple[str, bytes]]) -> Path:
	with tarfile.open(path, "w") as tar:
		for member in members:
			if isinstance(member, tarfile.TarInfo):
				tar.addfile(member)
			else:
				name, data = member
				info = tarfile.TarInfo(name)
				info.size = len(data)
				info.mode = 0o600
				tar.addfile(info, io.BytesIO(data))
	return path


def key_members(prefix: str = "fdroid/") -> list[tarfile.TarInfo | tuple[str, bytes]]:
	return [(f"{prefix}{f}", data) for f, data in CONTENT.items()]


def extracted(dest: Path) -> dict[str, bytes]:
	return {p.name: p.read_bytes() for p in sorted(dest.iterdir())}


@pytest.fixture
def dest(tmp_path: Path) -> Path:
	d = tmp_path / "dest"
	d.mkdir()
	return d


def test_extracts_exactly_the_four_members(tmp_path: Path, dest: Path):
	tar = make_tar(tmp_path / "b.tar", [*key_members(), ("fdroid/extra", b"x"), ("other", b"y")])
	container_keys.extract_keys(tar, dest)
	assert extracted(dest) == dict(sorted(CONTENT.items()))


def test_extracts_the_old_runbook_layout_with_a_directory_entry(tmp_path: Path, dest: Path):
	directory = tarfile.TarInfo("fdroid")
	directory.type = tarfile.DIRTYPE
	tar = make_tar(tmp_path / "b.tar", [directory, *key_members()])
	container_keys.extract_keys(tar, dest)
	assert extracted(dest) == dict(sorted(CONTENT.items()))


def test_extracts_a_gzipped_backup(tmp_path: Path, dest: Path):
	plain = make_tar(tmp_path / "b.tar", key_members())
	gz = tmp_path / "b.tar.gz"
	gz.write_bytes(gzip.compress(plain.read_bytes()))
	container_keys.extract_keys(gz, dest)
	assert extracted(dest) == dict(sorted(CONTENT.items()))


def test_the_last_of_duplicate_members_wins_like_tar(tmp_path: Path, dest: Path):
	tar = make_tar(tmp_path / "b.tar", [("fdroid/apk.pass", b"first"), *key_members()[:1], *key_members()[2:]])
	tar = make_tar(tmp_path / "b.tar", [("fdroid/apk.pass", b"first"), *key_members()])
	container_keys.extract_keys(tar, dest)
	assert (dest / "apk.pass").read_bytes() == CONTENT["apk.pass"]


def symlink(name: str) -> tarfile.TarInfo:
	info = tarfile.TarInfo(name)
	info.type = tarfile.SYMTYPE
	info.linkname = "/etc/shadow"
	return info


def hardlink(name: str) -> tarfile.TarInfo:
	info = tarfile.TarInfo(name)
	info.type = tarfile.LNKTYPE
	info.linkname = "fdroid/apk.p12"
	return info


@pytest.mark.parametrize(
	("members", "reason"),
	[
		(key_members()[:3], "missing fdroid/repo-index.pass"),
		(key_members("./fdroid/"), "missing fdroid/apk.p12"),
		(key_members("notif-fdroid/"), "missing"),
		([*key_members()[:3], symlink("fdroid/repo-index.pass")], "fdroid/repo-index.pass is not a regular file"),
		([*key_members()[:3], hardlink("fdroid/repo-index.pass")], "fdroid/repo-index.pass is not a regular file"),
		([*key_members()[:3], ("fdroid/repo-index.pass", b"x" * (container_keys.MAX_MEMBER_BYTES + 1))], "larger than"),
	],
)
def test_refuses_backups_without_four_regular_members(tmp_path: Path, dest: Path, members, reason):
	tar = make_tar(tmp_path / "b.tar", members)
	with pytest.raises(container_keys.BackupError, match=reason):
		container_keys.extract_keys(tar, dest)


def test_refuses_a_backup_with_too_many_members(tmp_path: Path, dest: Path):
	filler = [(f"junk/{n}", b"") for n in range(container_keys.MAX_MEMBERS)]
	tar = make_tar(tmp_path / "b.tar", [*filler, *key_members()])
	with pytest.raises(container_keys.BackupError, match="more than"):
		container_keys.extract_keys(tar, dest)


@pytest.mark.parametrize("data", [b"", b"random bytes, not a tar" * 50])
def test_refuses_what_is_not_a_tar(tmp_path: Path, dest: Path, data):
	tar = tmp_path / "b.tar"
	tar.write_bytes(data)
	with pytest.raises(container_keys.BackupError, match="."):
		container_keys.extract_keys(tar, dest)


def test_refuses_a_truncated_backup(tmp_path: Path, dest: Path):
	whole = make_tar(tmp_path / "b.tar", key_members()).read_bytes()
	truncated = tmp_path / "t.tar"
	truncated.write_bytes(whole[:1100])
	with pytest.raises(container_keys.BackupError, match="."):
		container_keys.extract_keys(truncated, dest)


def write_keys(directory: Path) -> None:
	directory.mkdir(exist_ok=True)
	for f, data in CONTENT.items():
		(directory / f).write_bytes(data)


def test_archive_round_trips_through_extract(tmp_path: Path, dest: Path):
	keys = tmp_path / "keys"
	write_keys(keys)
	out = io.BytesIO()
	container_keys.archive(keys, out)
	with tarfile.open(fileobj=io.BytesIO(out.getvalue())) as tar:
		assert tar.getnames() == [f"fdroid/{f}" for f in container_keys.FILES]
		assert all(m.isreg() and isinstance(m.mtime, int) for m in tar.getmembers())
	backup = tmp_path / "backup.tar"
	backup.write_bytes(out.getvalue())
	container_keys.extract_keys(backup, dest)
	assert extracted(dest) == dict(sorted(CONTENT.items()))


def test_archive_refuses_a_missing_key_file(tmp_path: Path):
	keys = tmp_path / "keys"
	write_keys(keys)
	(keys / "repo-index.pass").unlink()
	with pytest.raises(container_keys.FatalError, match=r"^repo-index.pass is not a regular file$"):
		container_keys.archive(keys, io.BytesIO())


def test_inspect_absent_and_partial(tmp_path: Path):
	keys = tmp_path / "keys"
	keys.mkdir()
	assert container_keys.inspect(keys) == "absent"
	(keys / "apk.p12").write_bytes(b"x")
	(keys / "repo-index.pass").write_bytes(b"x")
	assert container_keys.inspect(keys) == "partial apk.p12 repo-index.pass"


def test_install_never_replaces_an_existing_file(tmp_path: Path):
	stage = tmp_path / "stage"
	write_keys(stage)
	keys = tmp_path / "keys"
	keys.mkdir()
	(keys / "repo-index.p12").write_bytes(b"existing")
	with pytest.raises(container_keys.FatalError, match=r"^cannot install repo-index.p12"):
		container_keys.install_from(stage, keys)
	assert (keys / "repo-index.p12").read_bytes() == b"existing"


def test_install_links_all_four(tmp_path: Path):
	stage = tmp_path / "stage"
	write_keys(stage)
	keys = tmp_path / "keys"
	keys.mkdir()
	container_keys.install_from(stage, keys)
	assert extracted(keys) == dict(sorted(CONTENT.items()))


def test_staging_is_removed_afterwards_even_on_failure(tmp_path: Path):
	keys = tmp_path / "keys"
	keys.mkdir()
	(keys / ".staging").mkdir()
	(keys / ".staging" / "left-over").write_bytes(b"x")
	with pytest.raises(RuntimeError, match="boom"), container_keys.staging(keys) as stage:
		assert list(stage.iterdir()) == []
		raise RuntimeError("boom")
	assert list(keys.iterdir()) == []


@pytest.mark.parametrize(
	"environ",
	[
		{"APK_CERT_SHA256": "a" * 64},
		{"REPO_CERT_SHA256": "b" * 64},
		{"APK_CERT_SHA256": "A" * 64, "REPO_CERT_SHA256": "b" * 64},
	],
)
def test_restore_wants_both_pins_or_neither(tmp_path: Path, environ):
	tar = make_tar(tmp_path / "b.tar", key_members())
	keys = tmp_path / "keys"
	keys.mkdir()
	with pytest.raises(container_keys.FatalError, match="^set both pins or neither$"):
		container_keys.restore(tar, keys, environ)
	assert list(keys.iterdir()) == []


def test_restore_refuses_a_damaged_backup_and_installs_nothing(tmp_path: Path):
	tar = make_tar(tmp_path / "b.tar", key_members()[:3])
	keys = tmp_path / "keys"
	keys.mkdir()
	with pytest.raises(container_keys.FatalError, match=r"^the backup does not hold fdroid/\{apk.p12,"):
		container_keys.restore(tar, keys, {})
	assert list(keys.iterdir()) == []


def test_restore_refuses_when_any_key_file_exists(tmp_path: Path):
	tar = make_tar(tmp_path / "b.tar", key_members())
	keys = tmp_path / "keys"
	keys.mkdir()
	(keys / "apk.pass").write_bytes(b"x")
	with pytest.raises(container_keys.FatalError, match="^refusing: the key directory already holds apk.pass$"):
		container_keys.restore(tar, keys, {})


@pytest.mark.parametrize(
	("argv", "message"),
	[
		([], "usage: container_keys.py inspect | generate | restore <tar> | archive"),
		(["inspect", "x"], "usage: container_keys.py inspect"),
		(["restore"], "usage: container_keys.py restore <tar>"),
		(["restore", "a", "b"], "usage: container_keys.py restore <tar>"),
	],
)
def test_usage(capsys, argv, message):
	assert container_keys.main(["container_keys.py", *argv], {}) == 1
	assert capsys.readouterr().err == f"notif-apk keys: {message}\n"
