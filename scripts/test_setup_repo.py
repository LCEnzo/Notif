"""Tests for scripts/setup_repo.py against scratch git repositories."""

import os
import shlex
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parent

EXPECTED_DRIVER = f"{shlex.quote(sys.executable)} scripts/secrets_baseline_merge.py %O %A %B %P"


def isolated_git_env(tmp_path):
	return {
		**os.environ,
		"GIT_CONFIG_GLOBAL": str(tmp_path / "no-global-gitconfig"),
		"GIT_CONFIG_SYSTEM": str(tmp_path / "no-system-gitconfig"),
	}


@pytest.fixture
def scratch_repo(tmp_path):
	repo = tmp_path / "repo"
	repo.mkdir()
	env = isolated_git_env(tmp_path)
	subprocess.run(["git", "init", "-q"], cwd=repo, env=env, check=True)
	(repo / ".githooks").mkdir()
	return repo, env


def run_setup(repo, env, *flags):
	return subprocess.run(
		[sys.executable, str(SCRIPTS_DIR / "setup_repo.py"), *flags],
		cwd=repo,
		env=env,
		capture_output=True,
		text=True,
		check=False,
	)


def label_lines(output, label):
	return [line for line in output.splitlines() if line.startswith(f"{label} ")]


def read_config(repo, env, key):
	process = subprocess.run(
		["git", "config", "--local", "--get", key],
		cwd=repo,
		env=env,
		capture_output=True,
		text=True,
		check=False,
	)
	return process.stdout.rstrip("\n") if process.returncode == 0 else None


def test_first_run_sets_all_keys(scratch_repo):
	repo, env = scratch_repo
	process = run_setup(repo, env)
	assert process.returncode == 0, process.stderr
	assert len(label_lines(process.stdout, "set")) == 3
	assert read_config(repo, env, "core.hooksPath") == ".githooks"
	assert read_config(repo, env, "merge.secrets-baseline.name") == "detect-secrets baseline three-way merge"
	assert read_config(repo, env, "merge.secrets-baseline.driver") == EXPECTED_DRIVER


def test_second_run_is_idempotent(scratch_repo):
	repo, env = scratch_repo
	assert run_setup(repo, env).returncode == 0
	process = run_setup(repo, env)
	assert process.returncode == 0, process.stderr
	assert len(label_lines(process.stdout, "ok")) == 3
	assert not label_lines(process.stdout, "set")
	assert not label_lines(process.stdout, "updated")


def test_quiet_hides_ok_lines(scratch_repo):
	repo, env = scratch_repo
	assert run_setup(repo, env).returncode == 0
	process = run_setup(repo, env, "--quiet")
	assert process.returncode == 0
	assert process.stdout == ""


def test_absolute_hooks_path_is_rewritten_and_reported(scratch_repo):
	repo, env = scratch_repo
	absolute = str(repo / ".githooks")
	subprocess.run(["git", "config", "--local", "core.hooksPath", absolute], cwd=repo, env=env, check=True)
	process = run_setup(repo, env)
	assert process.returncode == 0, process.stderr
	assert len(label_lines(process.stdout, "updated")) == 1
	assert absolute in process.stdout
	assert read_config(repo, env, "core.hooksPath") == ".githooks"


def test_check_reports_drift_without_writing(scratch_repo):
	repo, env = scratch_repo
	process = run_setup(repo, env, "--check")
	assert process.returncode == 1
	assert len(label_lines(process.stdout, "drift")) == 3
	assert read_config(repo, env, "core.hooksPath") is None


def test_check_passes_after_setup(scratch_repo):
	repo, env = scratch_repo
	assert run_setup(repo, env).returncode == 0
	process = run_setup(repo, env, "--check")
	assert process.returncode == 0, process.stdout
	assert "drift" not in process.stdout


def test_check_flags_mutated_key_then_run_repairs_it(scratch_repo):
	repo, env = scratch_repo
	assert run_setup(repo, env).returncode == 0
	subprocess.run(["git", "config", "--local", "core.hooksPath", "/elsewhere"], cwd=repo, env=env, check=True)
	check = run_setup(repo, env, "--check")
	assert check.returncode == 1
	assert "core.hooksPath" in check.stdout
	assert read_config(repo, env, "core.hooksPath") == "/elsewhere"
	repair = run_setup(repo, env)
	assert repair.returncode == 0
	assert len(label_lines(repair.stdout, "updated")) == 1
	assert "(was /elsewhere)" in repair.stdout
	assert read_config(repo, env, "core.hooksPath") == ".githooks"


def test_outside_a_repository_exits_two(tmp_path):
	bare_dir = tmp_path / "not-a-repo"
	bare_dir.mkdir()
	process = run_setup(bare_dir, isolated_git_env(tmp_path))
	assert process.returncode == 2
	assert "error:" in process.stderr
