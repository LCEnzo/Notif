"""Idempotent per-clone git setup for this repository.

Run `python scripts/setup_repo.py` once per clone, from anywhere inside it, with a stable
interpreter (bare python >= 3.9, stdlib only — no uv/venv required). Git refuses to run
hooks or merge drivers straight from tracked files, so this step wires the tracked tooling
into `git config --local`, which is shared by every worktree of the clone:

- `core.hooksPath=.githooks` — relative, so each worktree runs its own checkout's hooks;
  an existing absolute value (which pins all worktrees to one checkout) is rewritten and
  the old value printed.
- `merge.secrets-baseline.{name,driver}` — routes `.secrets.baseline` merges through
  scripts/secrets_baseline_merge.py (see .gitattributes). The driver command quotes
  `sys.executable` POSIX-style because git runs merge drivers via sh, on Windows too.

On POSIX, missing executable bits on `.githooks/` files produce warnings, never failures.
`--check` reports drift without writing and exits 1 on drift; `--quiet` hides ok lines.
Exit codes: 0 ok, 1 drift, 2 environment error.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path


class RepoSetupError(RuntimeError):
	"""The environment cannot be configured (git missing, not a repository, write failure)."""


def desired_config() -> list[tuple[str, str]]:
	driver = f"{shlex.quote(sys.executable)} scripts/secrets_baseline_merge.py %O %A %B %P"
	return [
		("core.hooksPath", ".githooks"),
		("merge.secrets-baseline.name", "detect-secrets baseline three-way merge"),
		("merge.secrets-baseline.driver", driver),
	]


def find_repo_root() -> Path:
	result = _run_git(["rev-parse", "--show-toplevel"], cwd=Path.cwd())
	if result.returncode != 0:
		raise RepoSetupError(f"not inside a git repository: {result.stderr.strip()}")
	return Path(result.stdout.strip())


def _run_git(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
	try:
		return subprocess.run(
			["git", *args],
			cwd=str(cwd),
			capture_output=True,
			text=True,
			encoding="utf-8",
			errors="replace",
			check=False,
		)
	except FileNotFoundError as exc:
		raise RepoSetupError("git executable not found on PATH") from exc


def _get_local_config(repo_root: Path, key: str) -> str | None:
	result = _run_git(["config", "--local", "--get", key], cwd=repo_root)
	if result.returncode != 0:
		return None
	return result.stdout.rstrip("\n")


def _set_local_config(repo_root: Path, key: str, value: str) -> None:
	result = _run_git(["config", "--local", key, value], cwd=repo_root)
	if result.returncode != 0:
		raise RepoSetupError(f"git config --local {key} failed: {result.stderr.strip()}")


def _hook_permission_warnings(repo_root: Path) -> list[str]:
	if os.name != "posix":
		return []
	hooks_dir = repo_root / ".githooks"
	if not hooks_dir.is_dir():
		return []
	return [
		f".githooks/{hook.name} is not executable (chmod +x .githooks/{hook.name})"
		for hook in sorted(hooks_dir.iterdir())
		if hook.is_file() and not os.access(str(hook), os.X_OK)
	]


def _report(label: str, message: str) -> None:
	print(f"{label:<8} {message}")


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Configure per-clone git plumbing for this repository.")
	parser.add_argument("--check", action="store_true", help="report drift without writing; exit 1 on drift")
	parser.add_argument("--quiet", action="store_true", help="hide ok lines")
	args = parser.parse_args(argv)

	try:
		repo_root = find_repo_root()
		drift = False
		for key, wanted in desired_config():
			current = _get_local_config(repo_root, key)
			if current == wanted:
				if not args.quiet:
					_report("ok", f"{key} = {wanted}")
				continue
			drift = True
			if args.check:
				shown = "<unset>" if current is None else current
				_report("drift", f"{key} = {shown} (want {wanted})")
			elif current is None:
				_set_local_config(repo_root, key, wanted)
				_report("set", f"{key} = {wanted}")
			else:
				_set_local_config(repo_root, key, wanted)
				_report("updated", f"{key} = {wanted} (was {current})")
		for warning in _hook_permission_warnings(repo_root):
			_report("warn", warning)
	except RepoSetupError as exc:
		print(f"error: {exc}", file=sys.stderr)
		return 2
	return 1 if args.check and drift else 0


if __name__ == "__main__":
	sys.exit(main())
