import os
import signal
import sys
import threading
from collections import deque
from pathlib import Path

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from tests.conftest import APK_PIN, REPO_PIN, FakeHost, Host, notif_apk, run_tool, shell_tool

HEX64 = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)
OTHER = "c" * 64


def mounts(argv: list[str]) -> list[str]:
	return [argv[i + 1] for i, word in enumerate(argv) if word == "--mount"]


# --- pins ---


@given(
	digest=HEX64,
	before=st.lists(st.sampled_from(["# a comment", "  # indented", "\t#", "", "   ", "\r"]), max_size=4),
	after=st.lists(st.sampled_from(["# a comment", "", " \t "]), max_size=3),
	pad=st.sampled_from(["", " ", "\t", "\r", "  \t"]),
)
def test_pin_with_comments_and_whitespace_parses_to_its_digest(digest, before, after, pad):
	text = "\n".join([*before, pad + digest + pad, *after])
	assert notif_apk.parse_pin(text) == digest


@pytest.mark.parametrize(
	("text", "expected"),
	[
		("", ""),
		("# only a comment\n", ""),
		("\n\n  \n", ""),
		# The shell version joins every non-comment line and drops inner whitespace.
		("a" * 32 + "\n" + "a" * 32 + "\n", "a" * 64),
		("a" * 32 + " " + "a" * 32, "a" * 64),
	],
)
def test_pin_values(text, expected):
	assert notif_apk.parse_pin(text) == expected


@pytest.mark.parametrize(
	"text",
	[
		"A" * 64,  # upper case
		"a" * 63,
		"a" * 65,
		"a" * 64 + " # trailing comment",  # a # mid-line is not a comment
		"g" + "a" * 63,
		chr(0xA0) + "a" * 64,  # non-breaking space is not [[:space:]]
		"a" * 64 + "\n" + "b" * 64,  # two digests
	],
)
def test_malformed_pins_are_refused(text):
	with pytest.raises(ValueError, match="^not 64 lowercase hex digits: "):
		notif_apk.parse_pin(text)


SED = shell_tool("sed")
TR = shell_tool("tr")
PIN_LINES = st.lists(
	st.sampled_from(["#c", "  # c", "\t#x", "\f#", "\v# y", "ab", " a b ", "", "\r", "x#y", "0 1", " \t\r", "# \r"]),
	max_size=6,
)


@pytest.mark.skipif(SED is None or TR is None, reason="needs POSIX sed and tr")
@settings(max_examples=300, deadline=None)
@given(text=st.one_of(st.text(alphabet="0a# \t\r\n\v\fxF", max_size=40), PIN_LINES.map("\n".join)))
def test_pin_text_matches_the_shell_pipeline(text):
	assert SED is not None
	assert TR is not None
	sed_out = run_tool([SED, "/^[[:space:]]*#/d"], text.encode())
	expected = run_tool([TR, "-d", "[:space:]"], sed_out).decode()
	assert notif_apk.pin_text(text) == expected


def test_one_pin_set_is_refused_by_every_command(vps: Host, capsys):
	vps.set_pins(APK_PIN, "")
	for args in (["build"], ["publish", str(vps.script)], ["export-keys"]):
		host = FakeHost()
		assert vps.run(*args, host=host) == 1
		assert "only one of deploy/fdroid/pins/{apk-cert,repo-index-cert}.sha256 has a value" in capsys.readouterr().err
		assert host.docker_runs() == []


def test_missing_pin_file_is_refused(vps: Host, capsys):
	(vps.fdroid_dir / "pins" / "repo-index-cert.sha256").unlink()
	assert vps.run("build", host=FakeHost()) == 1
	assert "refused: pin file deploy/fdroid/pins/repo-index-cert.sha256 does not exist" in capsys.readouterr().err


# --- key inspection and the state machine ---


def test_parse_inspection():
	a, b = "1" * 64, "2" * 64
	assert notif_apk.parse_inspection("absent\n") == notif_apk.Absent()
	assert notif_apk.parse_inspection("partial apk.p12 apk.pass") == notif_apk.Partial("apk.p12 apk.pass")
	assert notif_apk.parse_inspection(f"present {a} {b}") == notif_apk.Present(a, b)


@pytest.mark.parametrize(
	"out",
	["", "partial", "present", f"present {'1' * 64}", f"present {'1' * 64} {'A' * 64}", "absent x", "unknown"],
)
def test_unexpected_inspection_output_is_an_error(out):
	with pytest.raises(ValueError, match="^unexpected inspection output: "):
		notif_apk.parse_inspection(out)


# Written from the runbook's table, not from decide().
RUNBOOK_TABLE = {
	("present", True, False): "Verify",
	("present", True, True): "Verify",
	("present", False, False): "ReportUnpinned",
	("present", False, True): "ReportUnpinned",
	("absent", False, False): "Generate",
	("absent", True, False): "RefuseNeedsRestore",
	("absent", True, True): "Restore",
	("absent", False, True): "Restore",
	("partial", True, False): "RefusePartial",
	("partial", True, True): "RefusePartial",
	("partial", False, False): "RefusePartial",
	("partial", False, True): "RefusePartial",
}


@pytest.mark.parametrize(("row", "expected"), RUNBOOK_TABLE.items())
def test_decide_follows_the_runbook_table(row, expected):
	keys, pinned, restore = row
	state = {
		"present": notif_apk.Present("1" * 64, "2" * 64),
		"absent": notif_apk.Absent(),
		"partial": notif_apk.Partial("apk.p12"),
	}[keys]
	pins = notif_apk.Pins(APK_PIN, REPO_PIN) if pinned else None
	tar = Path("/tmp/keys.tar") if restore else None
	assert type(notif_apk.decide(state, pins, tar)).__name__ == expected


def test_paths_default_like_the_shell(tmp_path: Path):
	script = tmp_path / "c" / "deploy" / "fdroid" / "notif-apk"
	paths = notif_apk.Paths.from_env(script, {"HOME": "/home/luka", "NOTIF_FDROID_KEYS": ""})
	assert paths.keys_dir == Path("/etc/notif/fdroid")  # empty counts as unset
	assert paths.data_dir == Path("/srv/notif-fdroid")
	assert paths.work_root == Path("/home/luka/.cache/notif-apk")
	assert paths.link == Path("/usr/local/bin/notif-apk")
	assert paths.pickup == Path("/home/luka/notif-fdroid-keys.tar")
	assert paths.checkout == tmp_path / "c"
	xdg = notif_apk.Paths.from_env(script, {"HOME": "/home/luka", "XDG_CACHE_HOME": "/var/cache/l"})
	assert xdg.work_root == Path("/var/cache/l/notif-apk")


# --- the command line ---


def test_no_command_prints_usage_and_exits_2(vps: Host, capsys):
	assert vps.run(host=FakeHost()) == 2
	assert capsys.readouterr().err.startswith("Usage:\n  notif-apk setup [--restore <tar>]")
	assert vps.run("frobnicate", host=FakeHost()) == 2


def test_help_prints_usage_to_stdout(vps: Host, capsys):
	assert vps.run("--help", host=FakeHost()) == 0
	assert "notif-apk export-keys" in capsys.readouterr().out


@pytest.mark.parametrize(
	("args", "message"),
	[
		(["setup", "--bogus"], "notif-apk: usage: notif-apk setup [--restore <tar>]"),
		(["setup", "--restore"], "notif-apk: usage: notif-apk setup [--restore <tar>]"),
		(["setup", "--restore", "no-such.tar"], "notif-apk: not a file: no-such.tar"),
		(["build", "a", "b"], "notif-apk: usage: notif-apk build [commit]"),
		(["build", "--force"], "notif-apk: not a commit: --force"),
		(["publish"], "notif-apk: usage: notif-apk publish <apk>"),
		(["publish", "no-such.apk"], "notif-apk: not a file: no-such.apk"),
		(["export-keys", "x"], "notif-apk: usage: notif-apk export-keys"),
	],
)
def test_bad_arguments_are_refused_before_any_command(vps: Host, capsys, args, message):
	host = FakeHost()
	assert vps.run(*args, host=host) == 1
	assert capsys.readouterr().err == message + "\n"
	assert host.calls == []


# --- setup ---


def setup_prefix(vps: Host) -> list[list[str]]:
	return [
		["sudo", "install", "-d", "-m", "0700", "-o", "root", "-g", "root", "--", str(vps.keys)],
		[
			"sudo",
			"install",
			"-d",
			"-m",
			"0755",
			"-o",
			"root",
			"-g",
			"root",
			"--",
			str(vps.data),
			str(vps.data / "repo"),
		],
		["sudo", "ln", "-sfT", "--", str(vps.script), str(vps.link)],
		["docker", "build", "--quiet", "--tag", "notif-apk-publish", "-"],
	]


def test_setup_generates_keys_when_there_are_none_and_no_pins(vps: Host, capsys):
	a, b = "1" * 64, "2" * 64
	host = FakeHost(inspect=deque(["absent", f"present {a} {b}"]))
	assert vps.run("setup", host=host) == 0
	assert host.calls[:4] == setup_prefix(vps)
	runs = host.docker_runs()
	assert [r[-1] for r in runs] == ["inspect", "generate", "inspect"]
	assert [f"type=bind,src={vps.keys},dst=/keys,readonly" in mounts(r) for r in runs] == [True, False, True]
	assert f"type=bind,src={vps.keys},dst=/keys" in mounts(runs[1])
	assert host.locks == [vps.data]
	out = capsys.readouterr().out
	assert f"notif-apk:       echo {a} >>deploy/fdroid/pins/apk-cert.sha256" in out
	assert f"notif-apk:       echo {b} >>deploy/fdroid/pins/repo-index-cert.sha256" in out
	assert out.index("Back them up") < out.index("Commit the pins")


def test_setup_runs_without_sudo_as_root(vps: Host):
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]))
	vps.set_pins(APK_PIN, REPO_PIN)
	assert notif_apk.main(["notif-apk", "setup"], vps.environ, host, script=vps.script, as_root=True) == 0
	assert host.calls[0][:2] == ["install", "-d"]


def test_setup_verifies_keys_that_match_the_pins(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", host=host) == 0
	assert f"notif-apk: the keys in {vps.keys} match the pins" in capsys.readouterr().out
	assert [r[-1] for r in host.docker_runs()] == ["inspect"]
	assert host.locks == []


@pytest.mark.parametrize(
	("disk", "message"),
	[
		(f"present {OTHER} {REPO_PIN}", f"the APK key in {{keys}} has cert SHA-256 {OTHER}, but the pin is {APK_PIN}"),
		(
			f"present {APK_PIN} {OTHER}",
			f"the repo index key in {{keys}} has cert SHA-256 {OTHER}, but the pin is {REPO_PIN}",
		),
	],
)
def test_setup_refuses_keys_that_do_not_match_the_pins(vps: Host, capsys, disk, message):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost(inspect=deque([disk]))
	assert vps.run("setup", host=host) == 1
	err = capsys.readouterr().err
	assert f"notif-apk: refused: {message.format(keys=vps.keys)}; not touching it (runbook: refusals)" in err
	assert [r[-1] for r in host.docker_runs()] == ["inspect"]


def test_setup_refuses_a_partial_key_set(vps: Host, capsys):
	host = FakeHost(inspect=deque(["partial apk.p12 apk.pass"]))
	assert vps.run("setup", host=host) == 1
	assert f"refused: {vps.keys} holds only apk.p12 apk.pass of the four key files" in capsys.readouterr().err
	assert [r[-1] for r in host.docker_runs()] == ["inspect"]


def test_setup_refuses_to_generate_when_the_pins_are_set(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost(inspect=deque(["absent"]))
	assert vps.run("setup", host=host) == 1
	assert "restore them with ./deploy.sh --fdroid-restore <backup tar>" in capsys.readouterr().err
	assert [r[-1] for r in host.docker_runs()] == ["inspect"]


def test_setup_restores_and_checks_against_the_pins(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	tar = vps.root / "backup.tar"
	tar.write_bytes(b"x")
	host = FakeHost(inspect=deque(["absent", f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", "--restore", str(tar), host=host) == 0
	restore = host.docker_runs()[1]
	assert restore[-2:] == ["restore", "/in/backup.tar"]
	assert f"type=bind,src={vps.keys},dst=/keys" in mounts(restore)
	assert f"type=bind,src={tar.resolve()},dst=/in/backup.tar,readonly" in mounts(restore)
	assert [f"APK_CERT_SHA256={APK_PIN}", f"REPO_CERT_SHA256={REPO_PIN}"] == [
		restore[i + 1] for i, word in enumerate(restore) if word == "--env"
	]
	assert host.locks == [vps.data]
	out = capsys.readouterr().out
	assert f"notif-apk: restored; the keys in {vps.keys} match the pins" in out
	assert f"shred it: shred -u -- {tar.resolve()}" in out


def test_setup_restores_unchecked_without_pins(vps: Host, capsys):
	tar = vps.root / "backup.tar"
	tar.write_bytes(b"x")
	host = FakeHost(inspect=deque(["absent", f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", "--restore", str(tar), host=host) == 0
	restore = host.docker_runs()[1]
	assert [restore[i + 1] for i, word in enumerate(restore) if word == "--env"] == [
		"APK_CERT_SHA256=",
		"REPO_CERT_SHA256=",
	]
	assert "The signing keys are not pinned yet" in capsys.readouterr().out


def test_setup_ignores_restore_when_keys_exist(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	tar = vps.root / "backup.tar"
	tar.write_bytes(b"x")
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", "--restore", str(tar), host=host) == 0
	assert f"notif-apk: warning: --restore ignored: {vps.keys} already holds keys" in capsys.readouterr().err
	assert [r[-1] for r in host.docker_runs()] == ["inspect"]


def test_setup_warns_about_a_leftover_export(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	vps.pickup.write_bytes(b"x")
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", host=host) == 0
	assert f"{vps.pickup} still holds a copy of the keys" in capsys.readouterr().err


@pytest.mark.parametrize(
	("host", "message"),
	[
		(FakeHost(statuses={"inspect": 1}), "refused: cannot read the keys in {keys} (see above); not touching them"),
		(FakeHost(inspect=deque(["what"])), "unexpected key inspection output: what"),
		(FakeHost(inspect=deque(["absent"]), statuses={"generate": 1}), "generating the keys failed (see above)"),
		(FakeHost(inspect=deque(["absent", "absent"])), "generating left {keys} absent"),
		(FakeHost(inspect=deque(["absent"]), lock_free=False), "another notif-apk run is in progress"),
		(FakeHost(statuses={"build": 1}), "docker build notif-apk-publish failed (see above)"),
	],
)
def test_setup_failures(vps: Host, capsys, host, message):
	assert vps.run("setup", host=host) == 1
	assert capsys.readouterr().err.endswith(f"notif-apk: {message.format(keys=vps.keys)}\n")


def test_a_failing_sudo_stops_setup_with_its_status(vps: Host):
	host = FakeHost(statuses={"install": 5})
	assert vps.run("setup", host=host) == 5
	assert len(host.calls) == 1


# --- export-keys ---


def test_export_keys_writes_the_archive_and_nothing_else(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]), archive_bytes=b"the archive")
	assert vps.run("export-keys", host=host) == 0
	assert vps.pickup.read_bytes() == b"the archive"
	assert sorted(p.name for p in vps.pickup.parent.iterdir()) == ["notif-fdroid-keys.tar"]
	archive = host.docker_runs()[1]
	assert archive[-1] == "archive"
	assert f"type=bind,src={vps.keys},dst=/keys,readonly" in mounts(archive)
	assert f"wrote {vps.pickup} (APK cert {APK_PIN}, repo index cert {REPO_PIN})" in capsys.readouterr().out
	assert host.calls[0][:2] == ["docker", "run"]  # no sudo


def test_export_keys_refuses_an_existing_pickup(vps: Host, capsys):
	vps.pickup.write_bytes(b"old")
	host = FakeHost()
	assert vps.run("export-keys", host=host) == 1
	assert f"refused: {vps.pickup} exists, left by an earlier export" in capsys.readouterr().err
	assert host.calls == []
	assert vps.pickup.read_bytes() == b"old"


@pytest.mark.skipif(sys.platform == "win32", reason="symlinks need privileges on Windows")
def test_export_keys_refuses_a_dangling_symlink_pickup(vps: Host):
	vps.pickup.symlink_to(vps.root / "nowhere")
	assert vps.run("export-keys", host=FakeHost()) == 1


@pytest.mark.parametrize(
	("pins", "host", "message"),
	[
		(None, FakeHost(inspect=deque(["absent"])), "refused: {keys} holds no complete key set (absent)"),
		((APK_PIN, REPO_PIN), FakeHost(inspect=deque([f"present {OTHER} {REPO_PIN}"])), "the APK key in {keys}"),
		(
			(APK_PIN, REPO_PIN),
			FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]), statuses={"archive": 1}),
			"archiving the keys failed (see above)",
		),
	],
)
def test_export_keys_failures_leave_no_file(vps: Host, capsys, pins, host, message):
	if pins:
		vps.set_pins(*pins)
	assert vps.run("export-keys", host=host) == 1
	assert message.format(keys=vps.keys) in capsys.readouterr().err
	assert list(vps.pickup.parent.iterdir()) == []


# --- build and publish ---


def test_build_refuses_without_pins(vps: Host, capsys):
	host = FakeHost()
	assert vps.run("build", host=host) == 1
	assert "refused: pin missing: deploy/fdroid/pins/*.sha256 have no value" in capsys.readouterr().err
	assert host.calls == []


def test_build_mounts_only_the_apk_key_and_publish_only_the_index_key(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost()
	assert vps.run("build", host=host) == 0
	checkout = str(vps.root / "checkout")
	assert host.calls[0] == ["git", "-C", checkout, "fetch", "--quiet", "origin"]
	assert host.calls[1][-1] == "origin/master^{commit}"
	build, publish = host.docker_runs()
	assert build[-3:] == ["/tool/container-build.sh", "674", "c0ffeec"]
	assert build[5:11] == ["--memory", "5g", "--memory-swap", "5g", "--cpus", "3"]
	build_secrets = [m for m in mounts(build) if "/run/secrets/" in m]
	assert [m.split(",")[2] for m in build_secrets] == ["dst=/run/secrets/apk.p12", "dst=/run/secrets/apk.pass"]
	assert all(m.endswith(",readonly") for m in build_secrets)
	publish_secrets = [m for m in mounts(publish) if "/run/secrets/" in m]
	assert [m.split(",")[2] for m in publish_secrets] == [
		"dst=/run/secrets/repo-index.p12",
		"dst=/run/secrets/repo-index.pass",
	]
	assert f"type=bind,src={vps.data / 'repo'},dst=/work/repo" in mounts(publish)
	apk_mount = next(m for m in mounts(publish) if "dst=/in/notif.apk" in m)
	assert apk_mount.endswith(f"{Path('out') / 'notif-674-c0ffeec.apk'},dst=/in/notif.apk,readonly")
	assert host.calls[-1][3:6] == ["worktree", "remove", "--force"]
	assert list(vps.work.iterdir()) == []
	assert "notif-apk: building c0ffeec, versionCode 674" in capsys.readouterr().out


def test_a_failed_build_exits_with_its_status_and_cleans_up(vps: Host):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost(statuses={"/tool/container-build.sh": 3})
	assert vps.run("build", "c0ffeec", host=host) == 3
	assert len(host.docker_runs()) == 1
	assert host.calls[-1][3:5] == ["worktree", "remove"]
	assert list(vps.work.iterdir()) == []


def test_build_refuses_an_unknown_commit(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost(statuses={"--verify": 1})
	assert vps.run("build", "nope", host=host) == 1
	assert capsys.readouterr().err == "notif-apk: not a commit: nope\n"
	assert host.docker_runs() == []


def test_build_needs_the_repo_directory(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	(vps.data / "repo").rmdir()
	assert vps.run("build", host=FakeHost()) == 1
	assert f"{vps.data}/repo does not exist" in capsys.readouterr().err


def test_publish_passes_the_container_status_through(vps: Host):
	vps.set_pins(APK_PIN, REPO_PIN)
	apk = vps.root / "x.apk"
	apk.write_bytes(b"apk")
	host = FakeHost(statuses={"/tool/publish_apk.py": 1})
	assert vps.run("publish", str(apk), host=host) == 1
	(publish,) = host.docker_runs()
	assert publish[-3:] == ["python3", "/tool/publish_apk.py", "/in/notif.apk"]
	assert [publish[i + 1] for i, word in enumerate(publish) if word == "--env"] == [
		f"APK_CERT_SHA256={APK_PIN}",
		f"REPO_CERT_SHA256={REPO_PIN}",
	]


def test_lock_held_refuses_publish(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	apk = vps.root / "x.apk"
	apk.write_bytes(b"apk")
	assert vps.run("publish", str(apk), host=FakeHost(lock_free=False)) == 1
	assert capsys.readouterr().err == "notif-apk: another notif-apk run is in progress\n"


# --- LocalHost: signals and the lock, on Linux ---

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="POSIX signals and flock")


@pytest.fixture
def local_host():
	saved = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
	host = notif_apk.LocalHost()
	host.install_signal_handlers()
	yield host
	for s, handler in saved.items():
		signal.signal(s, handler)
	signal.signal(signal.SIGHUP, signal.SIG_DFL)


@posix_only
def test_a_signal_during_a_command_waits_for_it(local_host):
	threading.Timer(0.2, os.kill, (os.getpid(), signal.SIGTERM)).start()
	with pytest.raises(notif_apk.Interrupted) as raised:
		local_host.capture([sys.executable, "-c", "import time; time.sleep(1); print('finished')"])
	assert raised.value.signum == signal.SIGTERM


@posix_only
def test_held_signals_are_only_recorded(local_host):
	local_host.hold_signals()
	os.kill(os.getpid(), signal.SIGINT)
	assert local_host.capture([sys.executable, "-c", "print('after')"]) == (0, "after")
	assert local_host.pending == signal.SIGINT


@posix_only
def test_the_lock_excludes_a_second_holder_and_is_inherited(tmp_path: Path):
	first = notif_apk.LocalHost()
	assert first.lock(tmp_path) is True
	assert notif_apk.LocalHost().lock(tmp_path) is False
	fd = first._fds[0]
	status, _ = first.capture([sys.executable, "-c", f"import os; os.fstat({fd})"])
	assert status == 0


@posix_only
def test_a_killed_command_reports_128_plus_the_signal():
	host = notif_apk.LocalHost()
	status = host.call([sys.executable, "-c", "import os, signal; os.kill(os.getpid(), signal.SIGKILL)"])
	assert status == 128 + signal.SIGKILL
