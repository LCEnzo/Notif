from collections import deque
from pathlib import Path

import pytest

from tests.conftest import APK_PIN, REPO_PIN, FakeHost, Host, mounts


@pytest.mark.parametrize(
	("args", "message"),
	[
		(["build", "a", "b"], "notif-apk: usage: notif-apk build [commit]"),
		(["build", "--force"], "notif-apk: not a commit: --force"),
		(["publish"], "notif-apk: usage: notif-apk publish <apk>"),
		(["publish", "no-such.apk"], "notif-apk: not a file: no-such.apk"),
	],
)
def test_bad_arguments_are_refused_before_any_command(vps: Host, capsys, args, message):
	host = FakeHost()
	assert vps.run(*args, host=host) == 1
	assert capsys.readouterr().err == message + "\n"
	assert host.calls == []


@pytest.mark.parametrize("command", ["build", "publish"])
def test_pins_are_required_before_any_command(vps: Host, capsys, command):
	args = [command] if command == "build" else [command, str(vps.script)]
	host = FakeHost()
	assert vps.run(*args, host=host) == 1
	assert "refused: pin missing: deploy/fdroid/pins/*.sha256 have no value" in capsys.readouterr().err
	vps.set_pins(APK_PIN, "")
	assert vps.run(*args, host=host) == 1
	assert "only one of deploy/fdroid/pins/{apk-cert,repo-index-cert}.sha256 has a value" in capsys.readouterr().err
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


def writable_binds(argv: list[str]) -> list[str]:
	"""The dst= of every bind mount without ,readonly."""
	binds = [m for m in mounts(argv) if m.startswith("type=bind,")]
	return [m.split(",")[2] for m in binds if not m.endswith(",readonly")]


def test_only_the_intended_mounts_are_writable(vps: Host):
	a, b = "1" * 64, "2" * 64
	vps.set_pins(APK_PIN, REPO_PIN)
	host = FakeHost()
	assert vps.run("build", host=host) == 0
	build, publish = host.docker_runs()
	assert writable_binds(build) == ["dst=/out"]
	assert writable_binds(publish) == ["dst=/work/repo"]

	vps.set_pins("", "")
	host = FakeHost(inspect=deque(["absent", f"present {a} {b}"]))
	assert vps.run("setup", host=host) == 0
	inspect, generate, inspect_again = host.docker_runs()
	assert writable_binds(inspect) == writable_binds(inspect_again) == []
	assert writable_binds(generate) == ["dst=/keys"]

	host = FakeHost(inspect=deque([f"present {a} {b}"]))
	assert vps.run("export-keys", host=host) == 0
	assert [writable_binds(r) for r in host.docker_runs()] == [[], []]

	tar = vps.root / "backup.tar"
	tar.write_bytes(b"x")
	host = FakeHost(inspect=deque(["absent", f"present {a} {b}"]))
	assert vps.run("setup", "--restore", str(tar), host=host) == 0
	assert writable_binds(host.docker_runs()[1]) == ["dst=/keys"]


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
	host = FakeHost(statuses={"/tool/publish_apk.py": 3})
	assert vps.run("publish", str(apk), host=host) == 3
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
