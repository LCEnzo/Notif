"""End-to-end: a real `git merge` resolves .secrets.baseline through the configured driver."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import secrets_baseline_merge as sbm
from test_secrets_baseline_merge import baseline, entry, entry_keys, find_entry

SCRIPTS_DIR = Path(__file__).resolve().parent


def git(repo, env, *args):
	process = subprocess.run(["git", *args], cwd=repo, env=env, capture_output=True, text=True, check=False)
	assert process.returncode == 0, f"git {' '.join(args)} failed: {process.stdout}{process.stderr}"
	return process


def write_baseline(repo, document):
	(repo / ".secrets.baseline").write_bytes(sbm.serialize_baseline(document).encode("utf-8"))


@pytest.mark.e2e
def test_divergent_baselines_merge_cleanly_through_the_driver(tmp_path):
	repo = tmp_path / "repo with space"
	(repo / "scripts").mkdir(parents=True)
	(repo / ".githooks").mkdir()
	shutil.copy(SCRIPTS_DIR / "secrets_baseline_merge.py", repo / "scripts")
	shutil.copy(SCRIPTS_DIR / "setup_repo.py", repo / "scripts")
	(repo / ".gitattributes").write_text("/.secrets.baseline merge=secrets-baseline text eol=lf\n", encoding="utf-8")

	env = {
		**os.environ,
		"GIT_CONFIG_GLOBAL": str(tmp_path / "no-global-gitconfig"),
		"GIT_CONFIG_SYSTEM": str(tmp_path / "no-system-gitconfig"),
	}
	git(repo, env, "init", "-q", "-b", "main")
	git(repo, env, "config", "--local", "user.name", "E2E Test")
	git(repo, env, "config", "--local", "user.email", "e2e@example.invalid")

	setup = subprocess.run(
		[sys.executable, "scripts/setup_repo.py", "--quiet"],
		cwd=repo,
		env=env,
		capture_output=True,
		text=True,
		check=False,
	)
	assert setup.returncode == 0, setup.stderr

	base = baseline(
		entry("f1.py", "h1", line=3, is_secret=False),
		entry("f2.py", "h2", line=8),
		generated_at="2026-08-01T00:00:00Z",
	)
	write_baseline(repo, base)
	git(repo, env, "add", "-A")
	git(repo, env, "commit", "-q", "-m", "base")

	git(repo, env, "checkout", "-q", "-b", "side")
	side = baseline(
		entry("f1.py", "h1", line=3, is_secret=True),
		entry("f2.py", "h2", line=8),
		entry("f3.py", "h4", line=2),
		generated_at="2026-08-03T00:00:00Z",
	)
	write_baseline(repo, side)
	git(repo, env, "commit", "-q", "-am", "side: audit h1, add h4")

	git(repo, env, "checkout", "-q", "main")
	main_doc = baseline(
		entry("f1.py", "h1", line=3, is_secret=False),
		entry("f1.py", "h3", line=11),
		generated_at="2026-08-02T00:00:00Z",
	)
	write_baseline(repo, main_doc)
	git(repo, env, "commit", "-q", "-am", "main: drop h2, add h3")

	git(repo, env, "merge", "--no-edit", "side")

	merged_text = (repo / ".secrets.baseline").read_text(encoding="utf-8").replace("\r\n", "\n")
	merged = json.loads(merged_text)

	assert entry_keys(merged) == {
		("f1.py", "Secret Keyword", "h1"),
		("f1.py", "Secret Keyword", "h3"),
		("f3.py", "Secret Keyword", "h4"),
	}
	assert entry_keys(merged) <= entry_keys(main_doc) | entry_keys(side)
	assert find_entry(merged, "h1")["is_secret"] is True
	assert find_entry(merged, "h2") is None
	assert merged["generated_at"] == "2026-08-03T00:00:00Z"
	assert sbm.serialize_baseline(merged) == merged_text

	status = git(repo, env, "status", "--porcelain")
	assert status.stdout == ""
