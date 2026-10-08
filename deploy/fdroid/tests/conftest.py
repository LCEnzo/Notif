import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import sys
from collections import deque
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from types import ModuleType
from typing import IO, Any

import pytest

FDROID_DIR = Path(__file__).resolve().parent.parent
APK_PIN = "a" * 64
REPO_PIN = "b" * 64


def load_notif_apk() -> ModuleType:
	"""notif-apk has no .py extension, so it is loaded by path."""
	path = FDROID_DIR / "notif-apk"
	loader = importlib.machinery.SourceFileLoader("notif_apk", str(path))
	spec = importlib.util.spec_from_loader("notif_apk", loader)
	assert spec is not None
	module = importlib.util.module_from_spec(spec)
	sys.modules["notif_apk"] = module
	loader.exec_module(module)
	return module


notif_apk: Any = load_notif_apk()


def shell_tool(name: str) -> str | None:
	"""A POSIX tool for the differential and rollback tests; None on Windows,
	where msys tools differ. CI sets FDROID_TESTS_REQUIRE_POSIX so that a
	missing tool fails the run instead of skipping those tests."""
	path = None if sys.platform == "win32" else shutil.which(name)
	if path is None and os.environ.get("FDROID_TESTS_REQUIRE_POSIX"):
		raise RuntimeError(f"FDROID_TESTS_REQUIRE_POSIX is set, but {name} is not available")
	return path


@dataclass
class FakeHost:
	"""Stands in for LocalHost: records every command and answers from a script."""

	inspect: deque[str] = field(default_factory=deque)
	statuses: dict[str, int] = field(default_factory=dict)
	archive_bytes: bytes = b"tar bytes"
	lock_free: bool = True
	calls: list[list[str]] = field(default_factory=list)
	locks: list[Path] = field(default_factory=list)

	def _status(self, argv: Sequence[str]) -> int:
		for word, status in self.statuses.items():
			if word in argv:
				return status
		return 0

	def call(self, argv: Sequence[str], *, stdin: IO[bytes] | None = None, stdout: int | None = None) -> int:
		self.calls.append(list(argv))
		status = self._status(argv)
		if status == 0 and "archive" in argv and stdout is not None:
			os.write(stdout, self.archive_bytes)
		if status == 0 and argv[3:5] == ["worktree", "add"]:
			Path(argv[-2]).mkdir(parents=True)
		if status == 0 and argv[3:5] == ["worktree", "remove"]:
			shutil.rmtree(argv[-1])
		return status

	def capture(self, argv: Sequence[str]) -> tuple[int, str]:
		self.calls.append(list(argv))
		status = self._status(argv)
		if "inspect" in argv:
			return status, self.inspect.popleft() if status == 0 else ""
		if "--verify" in argv:
			return status, "c0ffee" * 6 + "c0ff"
		if "--count" in argv:
			return status, "674"
		if "--short" in argv:
			return status, "c0ffeec"
		return status, ""

	def lock(self, directory: Path) -> bool:
		self.locks.append(directory)
		return self.lock_free

	def hold_signals(self) -> None:
		pass

	def docker_runs(self) -> list[list[str]]:
		return [c for c in self.calls if c[:2] == ["docker", "run"]]


@dataclass
class Host:
	"""A scratch VPS: a checkout with deploy/fdroid, and the override paths."""

	root: Path
	fdroid_dir: Path
	environ: dict[str, str]
	keys: Path
	data: Path
	work: Path
	link: Path
	pickup: Path

	@property
	def script(self) -> Path:
		return self.fdroid_dir / "notif-apk"

	def set_pins(self, apk: str, repo: str) -> None:
		(self.fdroid_dir / "pins" / "apk-cert.sha256").write_text(f"# comment\n{apk}\n", encoding="utf-8")
		(self.fdroid_dir / "pins" / "repo-index-cert.sha256").write_text(f"# comment\n{repo}\n", encoding="utf-8")

	def run(self, *args: str, host: FakeHost) -> int:
		return int(notif_apk.main(["notif-apk", *args], self.environ, host, script=self.script, as_root=False))


@pytest.fixture
def vps(tmp_path: Path) -> Host:
	fdroid_dir = tmp_path / "checkout" / "deploy" / "fdroid"
	(fdroid_dir / "pins").mkdir(parents=True)
	for name in ("notif-apk", "publish.Dockerfile", "build.Dockerfile"):
		(fdroid_dir / name).write_text("", encoding="utf-8")
	for name in ("apk-cert.sha256", "repo-index-cert.sha256"):
		(fdroid_dir / "pins" / name).write_text("# no value yet\n", encoding="utf-8")
	keys = tmp_path / "keys"
	data = tmp_path / "srv"
	(data / "repo").mkdir(parents=True)
	home = tmp_path / "home"
	home.mkdir()
	environ = {
		"HOME": str(home),
		"NOTIF_FDROID_KEYS": str(keys),
		"NOTIF_FDROID_DATA": str(data),
		"NOTIF_APK_WORK": str(tmp_path / "work"),
		"NOTIF_APK_LINK": str(tmp_path / "bin" / "notif-apk"),
		"NOTIF_FDROID_PICKUP": str(home / "notif-fdroid-keys.tar"),
	}
	return Host(
		root=tmp_path,
		fdroid_dir=fdroid_dir,
		environ=environ,
		keys=keys,
		data=data,
		work=tmp_path / "work",
		link=tmp_path / "bin" / "notif-apk",
		pickup=home / "notif-fdroid-keys.tar",
	)


def run_tool(argv: Sequence[str], data: bytes) -> bytes:
	result = subprocess.run(
		argv, input=data, stdout=subprocess.PIPE, check=True, env={"LC_ALL": "C", "PATH": os.defpath}
	)
	return result.stdout
