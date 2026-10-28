import os
import signal
import sys
import threading
from collections import deque
from pathlib import Path

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from tests.conftest import (
	APK_PIN,
	OTHER,
	REPO_PIN,
	FakeHost,
	Host,
	mounts,
	notif_apk,
	posix_only,
	run_tool,
	shell_tool,
)

HEX64 = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)


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


def test_one_pin_set_is_refused_before_any_command(vps: Host, capsys):
	vps.set_pins(APK_PIN, "")
	host = FakeHost()
	assert vps.run("export-keys", host=host) == 1
	assert "only one of deploy/fdroid/pins/{apk-cert,repo-index-cert}.sha256 has a value" in capsys.readouterr().err
	assert host.calls == []


def test_missing_pin_file_is_refused(vps: Host, capsys):
	(vps.fdroid_dir / "pins" / "repo-index-cert.sha256").unlink()
	assert vps.run("export-keys", host=FakeHost()) == 1
	assert "refused: pin file deploy/fdroid/pins/repo-index-cert.sha256 does not exist" in capsys.readouterr().err


# --- key inspection ---


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
	assert capsys.readouterr().err.startswith("Usage:\n  notif-apk ")
	assert vps.run("frobnicate", host=FakeHost()) == 2


def test_help_prints_usage_to_stdout(vps: Host, capsys):
	assert vps.run("--help", host=FakeHost()) == 0
	assert "notif-apk export-keys" in capsys.readouterr().out


def test_bad_arguments_are_refused_before_any_command(vps: Host, capsys):
	host = FakeHost()
	assert vps.run("export-keys", "x", host=host) == 1
	assert capsys.readouterr().err == "notif-apk: usage: notif-apk export-keys\n"
	assert host.calls == []


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
	("pins", "make_host", "message"),
	[
		(None, lambda: FakeHost(inspect=deque(["absent"])), "refused: {keys} holds no complete key set (absent)"),
		(
			(APK_PIN, REPO_PIN),
			lambda: FakeHost(inspect=deque([f"present {OTHER} {REPO_PIN}"])),
			"the APK key in {keys}",
		),
		(
			(APK_PIN, REPO_PIN),
			lambda: FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]), statuses={"archive": 1}),
			"archiving the keys failed (see above)",
		),
		(None, lambda: FakeHost(statuses={"inspect": 1}), "refused: cannot read the keys in {keys} (see above)"),
		(None, lambda: FakeHost(inspect=deque(["what"])), "unexpected key inspection output: what"),
	],
)
def test_export_keys_failures_leave_no_file(vps: Host, capsys, pins, make_host, message):
	if pins:
		vps.set_pins(*pins)
	assert vps.run("export-keys", host=make_host()) == 1
	assert message.format(keys=vps.keys) in capsys.readouterr().err
	assert list(vps.pickup.parent.iterdir()) == []


# --- LocalHost: signals, on Linux ---


@pytest.fixture
def local_host():
	saved = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
	host = notif_apk.LocalHost()
	host.install_signal_handlers()
	yield host
	for s, handler in saved.items():
		signal.signal(s, handler)
	signal.signal(signal.SIGHUP, signal.SIG_DFL)


def touch(marker: Path, delay: float = 0) -> list[str]:
	return [sys.executable, "-c", f"import pathlib, time; time.sleep({delay}); pathlib.Path({str(marker)!r}).touch()"]


@posix_only
def test_a_signal_during_a_command_waits_for_it_then_stops(local_host, tmp_path: Path):
	threading.Timer(0.2, os.kill, (os.getpid(), signal.SIGTERM)).start()
	with pytest.raises(notif_apk.Interrupted) as raised:
		local_host.call(touch(tmp_path / "finished", delay=1))
	assert raised.value.signum == signal.SIGTERM
	assert (tmp_path / "finished").exists()


@posix_only
def test_a_pending_signal_starts_no_further_command(local_host, tmp_path: Path):
	os.kill(os.getpid(), signal.SIGINT)
	with pytest.raises(notif_apk.Interrupted):
		local_host.call(touch(tmp_path / "started"))
	assert not (tmp_path / "started").exists()


@posix_only
def test_held_signals_are_only_recorded(local_host, tmp_path: Path):
	local_host.hold_signals()
	os.kill(os.getpid(), signal.SIGINT)
	assert local_host.call(touch(tmp_path / "cleanup")) == 0
	assert (tmp_path / "cleanup").exists()
	assert local_host.pending == signal.SIGINT


@posix_only
def test_a_signal_between_commands_ends_main_with_128_plus_n(vps: Host, local_host):
	os.kill(os.getpid(), signal.SIGTERM)
	status = notif_apk.main(["notif-apk", "export-keys"], vps.environ, local_host, script=vps.script, as_root=False)
	assert status == 128 + signal.SIGTERM
	assert list(vps.pickup.parent.iterdir()) == []  # stopped before the first command


@posix_only
def test_a_killed_command_reports_128_plus_the_signal():
	host = notif_apk.LocalHost()
	status = host.call([sys.executable, "-c", "import os, signal; os.kill(os.getpid(), signal.SIGKILL)"])
	assert status == 128 + signal.SIGKILL
