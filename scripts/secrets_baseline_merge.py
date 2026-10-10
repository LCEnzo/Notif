"""Three-way merge driver for detect-secrets baselines.

Git invokes this as `<python> scripts/secrets_baseline_merge.py %O %A %B %P` (wired up by
scripts/setup_repo.py); the merged result is written to %A and exit code 0 marks the merge
clean. Any nonzero exit leaves %A untouched, so git falls back to a normal text conflict.

Merge semantics, per entry keyed on (filename, type, hashed_secret), with filenames
normalized to forward slashes:

- `results` is a three-way set merge: additions survive, a one-sided deletion of an
  otherwise-untouched entry stays deleted, entries present on both sides get a
  field-level merge.
- Audit fields (`is_secret`, `is_verified`): the side that changed vs the ancestor wins;
  divergent changes are a conflict. Audits are never guessed.
- `line_number` never conflicts: the changed side wins, ours when both changed.
- Deletion on one side vs a pure line_number change on the other stays deleted; deletion
  vs any other field change is a conflict.
- `version` / `plugins_used` / `filters_used`: one-sided change wins, divergent changes
  conflict. `generated_at`: the later timestamp wins.
- Empty or missing %O is an empty baseline (add/add merge), not an error.

The baseline is never rescanned here: mid-merge tree state is incomplete. Output is
byte-identical to detect-secrets' own writer. Stdlib only; runs on bare python >= 3.9.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

EntryKey = tuple[str, str, str]

_MISSING: Any = object()
_CONFLICT: Any = object()

_TOP_FIELD_ORDER = ("version", "plugins_used", "filters_used", "results", "generated_at")
_ENTRY_FIELD_ORDER = ("type", "filename", "hashed_secret", "is_verified", "line_number", "is_secret")


class BaselineParseError(ValueError):
	"""The baseline file is not a well-formed detect-secrets baseline."""


class BaselineMergeConflict(Exception):
	"""The three sides diverge in a way this driver refuses to resolve automatically."""


def parse_baseline(text: str, label: str) -> dict[str, Any]:
	if not text.strip():
		return {}
	try:
		document = json.loads(text)
	except json.JSONDecodeError as exc:
		raise BaselineParseError(f"{label}: invalid JSON: {exc}") from exc
	if not isinstance(document, dict):
		raise BaselineParseError(f"{label}: baseline must be a JSON object, got {type(document).__name__}")
	results = document.get("results", _MISSING)
	if results is not _MISSING and not isinstance(results, dict):
		raise BaselineParseError(f"{label}: 'results' must be an object, got {type(results).__name__}")
	return document


def merge_baselines(ancestor: dict[str, Any], ours: dict[str, Any], theirs: dict[str, Any]) -> dict[str, Any]:
	ancestor_index = _index_results(ancestor, "ancestor")
	ours_index = _index_results(ours, "ours")
	theirs_index = _index_results(theirs, "theirs")

	merged_index: dict[EntryKey, dict[str, Any]] = {}
	for key in sorted(set(ours_index) | set(theirs_index)):
		if key in ours_index and key in theirs_index:
			entry: dict[str, Any] | None = _merge_entry(
				key, ancestor_index.get(key), ours_index[key], theirs_index[key]
			)
		elif key in ours_index:
			entry = _resolve_one_sided(key, ancestor_index.get(key), ours_index[key])
		else:
			entry = _resolve_one_sided(key, ancestor_index.get(key), theirs_index[key])
		if entry is not None:
			merged_index[key] = entry

	merged: dict[str, Any] = {}
	for field in _top_field_names(ancestor, ours, theirs):
		if field == "results":
			merged["results"] = _assemble_results(merged_index)
		elif field == "generated_at":
			timestamps = [doc["generated_at"] for doc in (ours, theirs) if "generated_at" in doc]
			if timestamps:
				merged["generated_at"] = max(timestamps)
		else:
			value = _merge_field(ancestor.get(field, _MISSING), ours.get(field, _MISSING), theirs.get(field, _MISSING))
			if value is _CONFLICT:
				raise BaselineMergeConflict(f"top-level field {field!r} changed divergently on both sides")
			if value is not _MISSING:
				merged[field] = value
	return merged


def serialize_baseline(document: dict[str, Any]) -> str:
	ordered = {field: document[field] for field in _TOP_FIELD_ORDER if field in document}
	for field in sorted(set(document) - set(_TOP_FIELD_ORDER)):
		ordered[field] = document[field]
	results = ordered.get("results")
	if isinstance(results, dict):
		ordered["results"] = {
			filename: [_order_entry_fields(entry) for entry in sorted(entries, key=_entry_sort_key)]
			for filename, entries in sorted(results.items())
		}
	return json.dumps(ordered, indent=2) + "\n"


def _normalize_filename(filename: str) -> str:
	return filename.replace("\\", "/")


def _index_results(document: dict[str, Any], label: str) -> dict[EntryKey, dict[str, Any]]:
	index: dict[EntryKey, dict[str, Any]] = {}
	results = document.get("results", {})
	if not isinstance(results, dict):
		raise BaselineParseError(f"{label}: 'results' must be an object, got {type(results).__name__}")
	for raw_filename, entries in results.items():
		if not isinstance(entries, list):
			raise BaselineParseError(f"{label}: results[{raw_filename!r}] must be a list")
		filename = _normalize_filename(raw_filename)
		for entry in entries:
			if not isinstance(entry, dict):
				raise BaselineParseError(f"{label}: results[{raw_filename!r}] contains a non-object entry")
			secret_type = entry.get("type")
			hashed_secret = entry.get("hashed_secret")
			if not isinstance(secret_type, str) or not isinstance(hashed_secret, str):
				raise BaselineParseError(
					f"{label}: results[{raw_filename!r}] entry lacks string 'type'/'hashed_secret'"
				)
			key = (filename, secret_type, hashed_secret)
			if key in index:
				raise BaselineParseError(f"{label}: duplicate entry {key!r}")
			normalized = dict(entry)
			normalized["filename"] = filename
			index[key] = normalized
	return index


def _merge_field(ancestor: Any, ours: Any, theirs: Any) -> Any:
	if ours == theirs:
		return ours
	if ours == ancestor:
		return theirs
	if theirs == ancestor:
		return ours
	return _CONFLICT


def _merge_entry(
	key: EntryKey,
	ancestor: dict[str, Any] | None,
	ours: dict[str, Any],
	theirs: dict[str, Any],
) -> dict[str, Any]:
	base = ancestor if ancestor is not None else {}
	merged: dict[str, Any] = {}
	for field in _entry_field_names(base, ours, theirs):
		value = _merge_field(base.get(field, _MISSING), ours.get(field, _MISSING), theirs.get(field, _MISSING))
		if value is _CONFLICT:
			if field == "line_number":
				value = ours.get(field, _MISSING)
			else:
				filename, secret_type, hashed_secret = key
				raise BaselineMergeConflict(
					f"{filename}: {secret_type} {hashed_secret}: field {field!r} changed divergently on both sides"
				)
		if value is not _MISSING:
			merged[field] = value
	return merged


def _resolve_one_sided(
	key: EntryKey,
	ancestor: dict[str, Any] | None,
	survivor: dict[str, Any],
) -> dict[str, Any] | None:
	if ancestor is None:
		return dict(survivor)
	if _without_line_number(survivor) == _without_line_number(ancestor):
		return None
	filename, secret_type, hashed_secret = key
	raise BaselineMergeConflict(
		f"{filename}: {secret_type} {hashed_secret}: deleted on one side but modified on the other"
	)


def _without_line_number(entry: dict[str, Any]) -> dict[str, Any]:
	return {field: value for field, value in entry.items() if field != "line_number"}


def _entry_field_names(*entries: dict[str, Any]) -> list[str]:
	names: set = set()
	for entry in entries:
		names.update(entry)
	ordered = [field for field in _ENTRY_FIELD_ORDER if field in names]
	ordered.extend(sorted(names - set(_ENTRY_FIELD_ORDER)))
	return ordered


def _top_field_names(*documents: dict[str, Any]) -> list[str]:
	names = {"results"}
	for document in documents:
		names.update(document)
	ordered = [field for field in _TOP_FIELD_ORDER if field in names]
	ordered.extend(sorted(names - set(_TOP_FIELD_ORDER)))
	return ordered


def _order_entry_fields(entry: dict[str, Any]) -> dict[str, Any]:
	ordered = {field: entry[field] for field in _ENTRY_FIELD_ORDER if field in entry}
	for field in sorted(set(entry) - set(_ENTRY_FIELD_ORDER)):
		ordered[field] = entry[field]
	return ordered


def _entry_sort_key(entry: dict[str, Any]) -> tuple[int, str, str]:
	return (entry.get("line_number", 0), entry["hashed_secret"], entry["type"])


def _assemble_results(index: dict[EntryKey, dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
	grouped: dict[str, list[dict[str, Any]]] = {}
	for (filename, _, _), entry in index.items():
		grouped.setdefault(filename, []).append(entry)
	return {
		filename: [_order_entry_fields(entry) for entry in sorted(grouped[filename], key=_entry_sort_key)]
		for filename in sorted(grouped)
	}


def _read_optional(path: str) -> str:
	try:
		return Path(path).read_text(encoding="utf-8")
	except FileNotFoundError:
		return ""


def main(argv: list[str]) -> int:
	if len(argv) not in (3, 4):
		print("usage: secrets_baseline_merge.py <ancestor> <ours> <theirs> [<path>]", file=sys.stderr)
		return 2
	ancestor_path, ours_path, theirs_path = argv[0], argv[1], argv[2]
	display_path = argv[3] if len(argv) == 4 else ours_path
	try:
		ancestor = parse_baseline(_read_optional(ancestor_path), "ancestor")
		ours = parse_baseline(Path(ours_path).read_text(encoding="utf-8"), "ours")
		theirs = parse_baseline(Path(theirs_path).read_text(encoding="utf-8"), "theirs")
		merged = merge_baselines(ancestor, ours, theirs)
	except BaselineParseError as exc:
		print(f"secrets-baseline merge driver: {display_path}: {exc}", file=sys.stderr)
		return 2
	except BaselineMergeConflict as exc:
		print(f"secrets-baseline merge driver: {display_path}: conflict: {exc}", file=sys.stderr)
		return 1
	Path(ours_path).write_bytes(serialize_baseline(merged).encode("utf-8"))
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
