"""Trim oversized RSS ``content:encoded`` CDATA blocks in feed fixtures.

Usage:
    uv run python monitoring/tests/scripts/snipFeedContent.py
    uv run python monitoring/tests/scripts/snipFeedContent.py --write
    uv run python monitoring/tests/scripts/snipFeedContent.py --max-content-bytes 200 --write monitoring/tests/citriniresearch.xml
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

SAMPLE_CONTENT = (
	'<div class="bbWrapper"><b>Ghostware Games!</b><br />'
	'<a href="https://forums.sufficientvelocity.com/threads/ghostware-games.150314/" '
	'class="link link--internal">Read more</a></div>'
)
DEFAULT_MAX_CONTENT_BYTES = len(SAMPLE_CONTENT.encode("utf-8"))

CONTENT_ENCODED_CDATA_RE = re.compile(
	r"(<content:encoded>\s*<!\[CDATA\[)(.*?)(\]\]>\s*</content:encoded>)",
	flags=re.DOTALL,
)
TRAILING_LINE_WHITESPACE_RE = re.compile(r"[ \t]+(\r?\n)")


@dataclass(frozen=True)
class SnipStats:
	path: Path
	blocks_seen: int
	blocks_snipped: int
	original_bytes: int
	snipped_bytes: int

	@property
	def bytes_saved(self) -> int:
		return self.original_bytes - self.snipped_bytes


def _snip_content(content: str, max_bytes: int) -> str:
	normalized_content = content.strip()
	if len(normalized_content.encode("utf-8")) <= max_bytes:
		return normalized_content

	return normalized_content.encode("utf-8")[:max_bytes].decode("utf-8", errors="ignore").rstrip()


def _strip_trailing_line_whitespace(xml: str) -> str:
	return TRAILING_LINE_WHITESPACE_RE.sub(r"\1", xml)


def snip_xml(xml: str, max_bytes: int) -> tuple[str, int, int]:
	blocks_seen = 0
	blocks_snipped = 0

	def replace(match: re.Match[str]) -> str:
		nonlocal blocks_seen, blocks_snipped

		blocks_seen += 1
		prefix, content, suffix = match.groups()
		snipped_content = _snip_content(content, max_bytes)
		if snipped_content != content:
			blocks_snipped += 1

		return f"{prefix}{snipped_content}{suffix}"

	snipped_xml = CONTENT_ENCODED_CDATA_RE.sub(replace, xml)
	return _strip_trailing_line_whitespace(snipped_xml), blocks_seen, blocks_snipped


def snip_file(path: Path, max_bytes: int, write: bool) -> SnipStats:
	original = path.read_text(encoding="utf-8")
	snipped, blocks_seen, blocks_snipped = snip_xml(original, max_bytes)

	if write and snipped != original:
		path.write_text(snipped, encoding="utf-8")

	return SnipStats(
		path=path,
		blocks_seen=blocks_seen,
		blocks_snipped=blocks_snipped,
		original_bytes=len(original.encode("utf-8")),
		snipped_bytes=len(snipped.encode("utf-8")),
	)


def _default_paths() -> list[Path]:
	return sorted(Path(__file__).resolve().parents[1].glob("*.xml"))


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(
		description=(
			"Trim RSS content:encoded CDATA blocks in feed fixtures. "
			f"The default cap is {DEFAULT_MAX_CONTENT_BYTES} UTF-8 bytes, matching the provided SV example body."
		)
	)
	parser.add_argument(
		"paths",
		nargs="*",
		type=Path,
		help="XML fixture paths. Defaults to all *.xml files in monitoring/tests.",
	)
	parser.add_argument(
		"--max-content-bytes",
		type=int,
		default=DEFAULT_MAX_CONTENT_BYTES,
		help="Maximum UTF-8 bytes to keep inside each content:encoded CDATA block.",
	)
	parser.add_argument(
		"--max-content-chars",
		type=int,
		default=None,
		help="Deprecated alias for --max-content-bytes. Kept for older local commands.",
	)
	parser.add_argument(
		"--write",
		action="store_true",
		help="Rewrite files in place. Without this flag, only reports what would change.",
	)
	return parser.parse_args()


def main() -> int:
	args = parse_args()
	max_content_bytes = args.max_content_chars or args.max_content_bytes
	if max_content_bytes < 1:
		raise SystemExit("--max-content-bytes must be at least 1")

	paths = args.paths or _default_paths()
	if not paths:
		raise SystemExit("No XML files found.")

	stats = [snip_file(path, max_content_bytes, args.write) for path in paths]
	total_saved = sum(item.bytes_saved for item in stats)
	total_snipped = sum(item.blocks_snipped for item in stats)
	action = "snipped" if args.write else "would snip"

	for item in stats:
		print(
			f"{item.path}: {item.blocks_snipped}/{item.blocks_seen} content blocks {action}; "
			f"{item.original_bytes} -> {item.snipped_bytes} bytes "
			f"({item.bytes_saved} saved)"
		)

	print(f"Total: {total_snipped} content blocks {action}; {total_saved} bytes saved")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
