"""Unit, CLI, and property tests for the .secrets.baseline merge driver."""

import ast
import json
import subprocess
import sys
from pathlib import Path

import pytest
import secrets_baseline_merge as sbm
from hypothesis import given, settings
from hypothesis import strategies as st

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS_DIR.parent

PLUGINS = [{"name": "KeywordDetector", "keyword_exclude": ""}]
FILTERS = [{"path": "detect_secrets.filters.heuristic.is_likely_id_string"}]


def entry(filename, hashed_secret, *, type_="Secret Keyword", line=1, is_secret=False, is_verified=False):
	data = {
		"type": type_,
		"filename": filename,
		"hashed_secret": hashed_secret,
		"is_verified": is_verified,
		"line_number": line,
	}
	if is_secret is not None:
		data["is_secret"] = is_secret
	return data


def baseline(*entries, version="1.5.0", generated_at="2026-08-01T00:00:00Z"):
	results = {}
	for item in entries:
		results.setdefault(item["filename"], []).append(item)
	return {
		"version": version,
		"plugins_used": PLUGINS,
		"filters_used": FILTERS,
		"results": results,
		"generated_at": generated_at,
	}


def entry_keys(document):
	return {
		(filename.replace("\\", "/"), item["type"], item["hashed_secret"])
		for filename, items in document.get("results", {}).items()
		for item in items
	}


def find_entry(document, hashed_secret):
	for items in document["results"].values():
		for item in items:
			if item["hashed_secret"] == hashed_secret:
				return item
	return None


class TestSerialization:
	def test_round_trip_real_baseline_is_byte_identical(self):
		text = (REPO_ROOT / ".secrets.baseline").read_text(encoding="utf-8").replace("\r\n", "\n")
		assert sbm.serialize_baseline(json.loads(text)) == text

	def test_serialize_orders_files_entries_and_fields(self):
		def scrambled(item, *drop):
			return {field: item[field] for field in sorted(item, reverse=True) if field not in drop}

		document = {
			"generated_at": "2026-08-01T00:00:00Z",
			"results": {
				"b.py": [
					scrambled(entry("b.py", "h2", line=9, is_secret=None), "filename"),
					scrambled(entry("b.py", "h1", line=2, is_secret=None), "filename"),
				],
				"a.py": [scrambled(entry("a.py", "h0", type_="T", is_verified=True), "filename")],
			},
			"version": "1.5.0",
		}
		text = sbm.serialize_baseline(document)
		parsed = json.loads(text)
		assert list(parsed) == ["version", "results", "generated_at"]
		assert list(parsed["results"]) == ["a.py", "b.py"]
		assert [item["hashed_secret"] for item in parsed["results"]["b.py"]] == ["h1", "h2"]
		assert list(parsed["results"]["a.py"][0]) == [
			"type",
			"hashed_secret",
			"is_verified",
			"line_number",
			"is_secret",
		]


class TestResultsMerge:
	def test_identity_merge(self):
		document = baseline(entry("a.py", "h1"), entry("b.py", "h2", line=7))
		merged = sbm.merge_baselines(document, document, document)
		assert sbm.serialize_baseline(merged) == sbm.serialize_baseline(document)

	def test_disjoint_adds_are_both_kept(self):
		base = baseline(entry("a.py", "h1"))
		ours = baseline(entry("a.py", "h1"), entry("b.py", "h2"))
		theirs = baseline(entry("a.py", "h1"), entry("c.py", "h3"))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert entry_keys(merged) == entry_keys(ours) | entry_keys(theirs)

	def test_one_sided_delete_of_untouched_entry_stays_deleted(self):
		base = baseline(entry("a.py", "h1"), entry("b.py", "h2"))
		ours = baseline(entry("a.py", "h1"))
		theirs = baseline(entry("a.py", "h1"), entry("b.py", "h2"))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert entry_keys(merged) == {("a.py", "Secret Keyword", "h1")}

	def test_delete_vs_line_number_change_stays_deleted(self):
		base = baseline(entry("a.py", "h1"), entry("b.py", "h2", line=5))
		ours = baseline(entry("a.py", "h1"))
		theirs = baseline(entry("a.py", "h1"), entry("b.py", "h2", line=9))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert entry_keys(merged) == {("a.py", "Secret Keyword", "h1")}

	def test_delete_vs_audit_change_conflicts(self):
		base = baseline(entry("a.py", "h1"), entry("b.py", "h2", is_secret=False))
		ours = baseline(entry("a.py", "h1"))
		theirs = baseline(entry("a.py", "h1"), entry("b.py", "h2", is_secret=True))
		with pytest.raises(sbm.BaselineMergeConflict):
			sbm.merge_baselines(base, ours, theirs)

	def test_changed_audit_side_wins(self):
		base = baseline(entry("a.py", "h1", is_secret=False))
		ours = baseline(entry("a.py", "h1", is_secret=False))
		theirs = baseline(entry("a.py", "h1", is_secret=True))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert find_entry(merged, "h1")["is_secret"] is True

	def test_audit_added_on_one_side_wins(self):
		base = baseline(entry("a.py", "h1", is_secret=None))
		ours = baseline(entry("a.py", "h1", is_secret=None, is_verified=True))
		theirs = baseline(entry("a.py", "h1", is_secret=False))
		merged = sbm.merge_baselines(base, ours, theirs)
		item = find_entry(merged, "h1")
		assert item["is_secret"] is False
		assert item["is_verified"] is True

	def test_divergent_audit_conflicts(self):
		base = baseline(entry("a.py", "h1", is_secret=None))
		ours = baseline(entry("a.py", "h1", is_secret=True))
		theirs = baseline(entry("a.py", "h1", is_secret=False))
		with pytest.raises(sbm.BaselineMergeConflict):
			sbm.merge_baselines(base, ours, theirs)

	def test_line_number_divergence_takes_ours(self):
		base = baseline(entry("a.py", "h1", line=10))
		ours = baseline(entry("a.py", "h1", line=20))
		theirs = baseline(entry("a.py", "h1", line=30))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert find_entry(merged, "h1")["line_number"] == 20

	def test_line_number_single_change_wins(self):
		base = baseline(entry("a.py", "h1", line=10))
		ours = baseline(entry("a.py", "h1", line=10))
		theirs = baseline(entry("a.py", "h1", line=30))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert find_entry(merged, "h1")["line_number"] == 30

	def test_backslash_and_forward_slash_filenames_are_one_entry(self):
		base = baseline(entry("dir\\f.py", "h1", line=3))
		ours = baseline(entry("dir/f.py", "h1", line=3))
		theirs = baseline(entry("dir\\f.py", "h1", line=8))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert list(merged["results"]) == ["dir/f.py"]
		assert find_entry(merged, "h1")["filename"] == "dir/f.py"
		assert find_entry(merged, "h1")["line_number"] == 8

	def test_empty_ancestor_is_add_add(self):
		ancestor = sbm.parse_baseline("", "ancestor")
		ours = baseline(entry("a.py", "h1"))
		theirs = baseline(entry("b.py", "h2"))
		merged = sbm.merge_baselines(ancestor, ours, theirs)
		assert entry_keys(merged) == entry_keys(ours) | entry_keys(theirs)

	def test_add_add_of_same_entry_with_divergent_audit_conflicts(self):
		ours = baseline(entry("a.py", "h1", is_secret=True))
		theirs = baseline(entry("a.py", "h1", is_secret=False))
		with pytest.raises(sbm.BaselineMergeConflict):
			sbm.merge_baselines({}, ours, theirs)


class TestTopLevelMerge:
	def test_generated_at_takes_later_timestamp(self):
		base = baseline(entry("a.py", "h1"), generated_at="2026-08-01T00:00:00Z")
		ours = baseline(entry("a.py", "h1"), generated_at="2026-08-03T00:00:00Z")
		theirs = baseline(entry("a.py", "h1"), generated_at="2026-08-02T00:00:00Z")
		merged = sbm.merge_baselines(base, ours, theirs)
		assert merged["generated_at"] == "2026-08-03T00:00:00Z"

	def test_one_sided_plugin_change_wins(self):
		new_plugins = [*PLUGINS, {"name": "StripeDetector"}]
		base = baseline(entry("a.py", "h1"))
		ours = baseline(entry("a.py", "h1"))
		ours["plugins_used"] = new_plugins
		theirs = baseline(entry("a.py", "h1"))
		merged = sbm.merge_baselines(base, ours, theirs)
		assert merged["plugins_used"] == new_plugins

	def test_divergent_version_conflicts(self):
		base = baseline(entry("a.py", "h1"), version="1.5.0")
		ours = baseline(entry("a.py", "h1"), version="1.6.0")
		theirs = baseline(entry("a.py", "h1"), version="1.7.0")
		with pytest.raises(sbm.BaselineMergeConflict):
			sbm.merge_baselines(base, ours, theirs)


class TestParsing:
	def test_invalid_json_raises(self):
		with pytest.raises(sbm.BaselineParseError):
			sbm.parse_baseline("{not json", "ours")

	def test_non_dict_document_raises(self):
		with pytest.raises(sbm.BaselineParseError):
			sbm.parse_baseline("[1, 2]", "ours")

	def test_non_dict_results_raises(self):
		with pytest.raises(sbm.BaselineParseError):
			sbm.parse_baseline('{"results": []}', "ours")

	def test_duplicate_entry_raises(self):
		document = baseline(entry("dir\\f.py", "h1"))
		document["results"]["dir/f.py"] = [entry("dir/f.py", "h1")]
		with pytest.raises(sbm.BaselineParseError):
			sbm.merge_baselines({}, document, {"results": {}})

	def test_empty_text_is_empty_baseline(self):
		assert sbm.parse_baseline("", "ancestor") == {}
		assert sbm.parse_baseline("  \n", "ancestor") == {}


class TestCli:
	def run_driver(self, tmp_path, ancestor_text, ours_text, theirs_text):
		paths = []
		for name, text in (("O", ancestor_text), ("A", ours_text), ("B", theirs_text)):
			path = tmp_path / name
			path.write_bytes(text.encode("utf-8"))
			paths.append(path)
		process = subprocess.run(
			[sys.executable, str(SCRIPTS_DIR / "secrets_baseline_merge.py"), *map(str, paths), ".secrets.baseline"],
			capture_output=True,
			text=True,
			check=False,
		)
		return process, paths[1]

	def test_clean_merge_writes_ours_and_exits_zero(self, tmp_path):
		base = baseline(entry("a.py", "h1"))
		ours = baseline(entry("a.py", "h1"), entry("b.py", "h2"))
		theirs = baseline(entry("a.py", "h1"), entry("c.py", "h3"))
		process, ours_path = self.run_driver(
			tmp_path,
			sbm.serialize_baseline(base),
			sbm.serialize_baseline(ours),
			sbm.serialize_baseline(theirs),
		)
		assert process.returncode == 0, process.stderr
		expected = sbm.serialize_baseline(sbm.merge_baselines(base, ours, theirs))
		assert ours_path.read_bytes() == expected.encode("utf-8")

	def test_conflict_exits_one_and_leaves_ours_untouched(self, tmp_path):
		base = baseline(entry("a.py", "h1", is_secret=None))
		ours_text = sbm.serialize_baseline(baseline(entry("a.py", "h1", is_secret=True)))
		theirs = baseline(entry("a.py", "h1", is_secret=False))
		process, ours_path = self.run_driver(
			tmp_path,
			sbm.serialize_baseline(base),
			ours_text,
			sbm.serialize_baseline(theirs),
		)
		assert process.returncode == 1
		assert "conflict" in process.stderr
		assert ours_path.read_bytes() == ours_text.encode("utf-8")

	def test_unparseable_side_exits_nonzero_and_leaves_ours_untouched(self, tmp_path):
		ours_text = sbm.serialize_baseline(baseline(entry("a.py", "h1")))
		process, ours_path = self.run_driver(tmp_path, "", ours_text, "{broken")
		assert process.returncode == 2
		assert "invalid JSON" in process.stderr
		assert ours_path.read_bytes() == ours_text.encode("utf-8")

	def test_missing_ancestor_file_is_empty_baseline(self, tmp_path):
		ours = baseline(entry("a.py", "h1"))
		theirs = baseline(entry("a.py", "h1"))
		ours_path = tmp_path / "A"
		theirs_path = tmp_path / "B"
		ours_path.write_bytes(sbm.serialize_baseline(ours).encode("utf-8"))
		theirs_path.write_bytes(sbm.serialize_baseline(theirs).encode("utf-8"))
		process = subprocess.run(
			[
				sys.executable,
				str(SCRIPTS_DIR / "secrets_baseline_merge.py"),
				str(tmp_path / "does-not-exist"),
				str(ours_path),
				str(theirs_path),
			],
			capture_output=True,
			text=True,
			check=False,
		)
		assert process.returncode == 0, process.stderr


@pytest.mark.parametrize("script", ["secrets_baseline_merge.py", "setup_repo.py"])
def test_scripts_parse_under_python_39_grammar(script):
	source = (SCRIPTS_DIR / script).read_text(encoding="utf-8")
	ast.parse(source, feature_version=(3, 9))


_TYPES = st.sampled_from(["Secret Keyword", "Hex High Entropy String"])
_FILENAMES = st.sampled_from(["a.py", "pkg/b.py", "docs/c.md"])
_HASHES = st.sampled_from(["h1", "h2", "h3", "h4"])
_KEYS = st.tuples(_FILENAMES, _TYPES, _HASHES)
_TIMESTAMPS = st.sampled_from(["2026-08-01T00:00:00Z", "2026-08-02T00:00:00Z", "2026-08-03T00:00:00Z"])


@st.composite
def _entry_for_key(draw, key):
	filename, secret_type, hashed_secret = key
	data = {
		"type": secret_type,
		"filename": filename,
		"hashed_secret": hashed_secret,
		"is_verified": draw(st.booleans()),
		"line_number": draw(st.integers(min_value=1, max_value=5)),
	}
	audit = draw(st.sampled_from(["unaudited", "true", "false"]))
	if audit != "unaudited":
		data["is_secret"] = audit == "true"
	return data


@st.composite
def _baseline_for_keys(draw, keys):
	results = {}
	for key in keys:
		results.setdefault(key[0], []).append(draw(_entry_for_key(key)))
	return {
		"version": "1.5.0",
		"plugins_used": PLUGINS,
		"filters_used": FILTERS,
		"results": results,
		"generated_at": draw(_TIMESTAMPS),
	}


@st.composite
def _baseline_triples(draw):
	pool = draw(st.lists(_KEYS, unique=True, min_size=0, max_size=5))
	memberships = [draw(st.tuples(st.booleans(), st.booleans(), st.booleans())) for _ in pool]
	documents = []
	for side in range(3):
		keys = [key for key, member in zip(pool, memberships) if member[side]]
		documents.append(draw(_baseline_for_keys(keys)))
	return tuple(documents)


@pytest.mark.property
@settings(deadline=None, max_examples=200)
@given(triple=_baseline_triples())
def test_merged_hashes_are_a_subset_of_ours_union_theirs(triple):
	ancestor, ours, theirs = triple
	try:
		merged = sbm.merge_baselines(ancestor, ours, theirs)
	except sbm.BaselineMergeConflict:
		return
	assert entry_keys(merged) <= entry_keys(ours) | entry_keys(theirs)


@pytest.mark.property
@settings(deadline=None, max_examples=200)
@given(triple=_baseline_triples())
def test_no_entry_becomes_not_secret_unless_a_parent_said_so(triple):
	ancestor, ours, theirs = triple
	try:
		merged = sbm.merge_baselines(ancestor, ours, theirs)
	except sbm.BaselineMergeConflict:
		return
	parent_false_keys = set()
	for parent in (ours, theirs):
		for filename, items in parent["results"].items():
			for item in items:
				if item.get("is_secret") is False:
					parent_false_keys.add((filename, item["type"], item["hashed_secret"]))
	for filename, items in merged["results"].items():
		for item in items:
			if item.get("is_secret") is False:
				assert (filename, item["type"], item["hashed_secret"]) in parent_false_keys


@st.composite
def _single_baselines(draw):
	pool = draw(st.lists(_KEYS, unique=True, min_size=0, max_size=5))
	return draw(_baseline_for_keys(pool))


@pytest.mark.property
@settings(deadline=None, max_examples=100)
@given(document=_single_baselines())
def test_merge_of_identical_sides_is_byte_identical(document):
	merged = sbm.merge_baselines(document, document, document)
	assert sbm.serialize_baseline(merged) == sbm.serialize_baseline(document)
