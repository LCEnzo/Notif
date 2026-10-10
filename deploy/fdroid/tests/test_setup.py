import os
import sys
from collections import deque
from pathlib import Path

import pytest

from tests.conftest import APK_PIN, OTHER, REPO_PIN, FakeHost, Host, mounts, notif_apk, posix_only


def setup_prefix(vps: Host) -> list[list[str]]:
	return [
		["sudo", "install", "-d", "-m", "0700", "-o", "root", "-g", "root", "--", str(vps.keys)],
		["sudo", "install", "-d", "-m", "0755", "-o", "root", "-g", "root", "--", str(vps.data), str(vps.data / "repo")],
		["sudo", "ln", "-sfT", "--", str(vps.script), str(vps.link)],
		["docker", "build", "--quiet", "--tag", "notif-apk-publish", "-"],
	]  # fmt: skip


@pytest.mark.parametrize(
	("args", "message"),
	[
		(["setup", "--bogus"], "notif-apk: usage: notif-apk setup [--restore <tar>]"),
		(["setup", "--restore"], "notif-apk: usage: notif-apk setup [--restore <tar>]"),
		(["setup", "--restore", "no-such.tar"], "notif-apk: not a file: no-such.tar"),
	],
)
def test_bad_arguments_are_refused_before_any_command(vps: Host, capsys, args, message):
	host = FakeHost()
	assert vps.run(*args, host=host) == 1
	assert capsys.readouterr().err == message + "\n"
	assert host.calls == []


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


@pytest.mark.parametrize(("pinned", "restore"), [(False, False), (True, False), (False, True), (True, True)])
def test_setup_refuses_a_partial_key_set(vps: Host, capsys, pinned, restore):
	if pinned:
		vps.set_pins(APK_PIN, REPO_PIN)
	tar = vps.root / "backup.tar"
	tar.write_bytes(b"x")
	host = FakeHost(inspect=deque(["partial apk.p12 apk.pass"]))
	assert vps.run("setup", *(["--restore", str(tar)] if restore else []), host=host) == 1
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


@pytest.mark.parametrize("pinned", [True, False])
def test_setup_ignores_restore_when_keys_exist(vps: Host, capsys, pinned):
	if pinned:
		vps.set_pins(APK_PIN, REPO_PIN)
	tar = vps.root / "backup.tar"
	tar.write_bytes(b"x")
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", "--restore", str(tar), host=host) == 0
	out, err = capsys.readouterr()
	assert f"notif-apk: warning: --restore ignored: {vps.keys} already holds keys" in err
	assert ("match the pins" in out) is pinned
	assert ("not pinned yet" in out) is not pinned
	assert [r[-1] for r in host.docker_runs()] == ["inspect"]


def test_setup_warns_about_a_leftover_export(vps: Host, capsys):
	vps.set_pins(APK_PIN, REPO_PIN)
	vps.pickup.write_bytes(b"x")
	host = FakeHost(inspect=deque([f"present {APK_PIN} {REPO_PIN}"]))
	assert vps.run("setup", host=host) == 0
	assert f"{vps.pickup} still holds a copy of the keys" in capsys.readouterr().err


def test_one_pin_set_is_refused_after_the_idempotent_steps(vps: Host, capsys):
	vps.set_pins(APK_PIN, "")
	host = FakeHost()
	assert vps.run("setup", host=host) == 1
	assert "only one of deploy/fdroid/pins/{apk-cert,repo-index-cert}.sha256 has a value" in capsys.readouterr().err
	assert host.calls == setup_prefix(vps)


@pytest.mark.parametrize(
	("make_host", "message"),
	[
		(
			lambda: FakeHost(statuses={"inspect": 1}),
			"refused: cannot read the keys in {keys} (see above); not touching them",
		),
		(lambda: FakeHost(inspect=deque(["what"])), "unexpected key inspection output: what"),
		(
			lambda: FakeHost(inspect=deque(["absent"]), statuses={"generate": 1}),
			"generating the keys failed (see above)",
		),
		(lambda: FakeHost(inspect=deque(["absent", "absent"])), "generating left {keys} absent"),
		(lambda: FakeHost(inspect=deque(["absent"]), lock_free=False), "another notif-apk run is in progress"),
		(lambda: FakeHost(statuses={"build": 1}), "docker build notif-apk-publish failed (see above)"),
	],
)
def test_setup_failures(vps: Host, capsys, make_host, message):
	assert vps.run("setup", host=make_host()) == 1
	assert capsys.readouterr().err.endswith(f"notif-apk: {message.format(keys=vps.keys)}\n")


def test_a_failing_sudo_stops_setup_with_its_status(vps: Host):
	host = FakeHost(statuses={"install": 5})
	assert vps.run("setup", host=host) == 5
	assert len(host.calls) == 1


@posix_only
def test_the_lock_is_exclusive_and_only_docker_inherits_it(tmp_path: Path, monkeypatch):
	first = notif_apk.LocalHost()
	assert first.lock(tmp_path) is True
	assert notif_apk.LocalHost().lock(tmp_path) is False
	fd = first._lock_fds[0]
	probe = f"import os, sys; os.fstat({fd})"
	bin_dir = tmp_path / "bin"
	bin_dir.mkdir()
	docker = bin_dir / "docker"
	docker.write_text(f"#!{sys.executable}\n{probe}\n", encoding="utf-8")
	docker.chmod(0o755)
	assert first.call([str(docker)]) != 0  # the path is not "docker"
	assert first.call([sys.executable, "-c", probe]) != 0
	monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
	assert first.call(["docker"]) == 0
