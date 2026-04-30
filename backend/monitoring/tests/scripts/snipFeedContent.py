"""Trim oversized RSS ``content:encoded`` CDATA blocks in feed fixtures.

Usage:
    uv run python monitoring/tests/scripts/snipFeedContent.py
    uv run python monitoring/tests/scripts/snipFeedContent.py --write
    uv run python monitoring/tests/scripts/snipFeedContent.py --max-content-chars 200 --write monitoring/tests/citriniresearch.xml
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
DEFAULT_MAX_CONTENT_CHARS = len(SAMPLE_CONTENT)

CONTENT_ENCODED_CDATA_RE = re.compile(
    r"(<content:encoded>\s*<!\[CDATA\[)(.*?)(\]\]>\s*</content:encoded>)",
    flags=re.DOTALL,
)


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


def _snip_content(content: str, max_chars: int) -> str:
    if len(content) <= max_chars:
        return content

    return content[:max_chars]


def snip_xml(xml: str, max_chars: int) -> tuple[str, int, int]:
    blocks_seen = 0
    blocks_snipped = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal blocks_seen, blocks_snipped

        blocks_seen += 1
        prefix, content, suffix = match.groups()
        snipped_content = _snip_content(content, max_chars)
        if snipped_content != content:
            blocks_snipped += 1

        return f"{prefix}{snipped_content}{suffix}"

    return CONTENT_ENCODED_CDATA_RE.sub(replace, xml), blocks_seen, blocks_snipped


def snip_file(path: Path, max_chars: int, write: bool) -> SnipStats:
    original = path.read_text(encoding="utf-8")
    snipped, blocks_seen, blocks_snipped = snip_xml(original, max_chars)

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
            f"The default cap is {DEFAULT_MAX_CONTENT_CHARS} characters, matching the provided SV example body."
        )
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="XML fixture paths. Defaults to all *.xml files in monitoring/tests.",
    )
    parser.add_argument(
        "--max-content-chars",
        type=int,
        default=DEFAULT_MAX_CONTENT_CHARS,
        help="Maximum characters to keep inside each content:encoded CDATA block.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Rewrite files in place. Without this flag, only reports what would change.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.max_content_chars < 1:
        raise SystemExit("--max-content-chars must be at least 1")

    paths = args.paths or _default_paths()
    if not paths:
        raise SystemExit("No XML files found.")

    stats = [snip_file(path, args.max_content_chars, args.write) for path in paths]
    total_saved = sum(item.bytes_saved for item in stats)
    total_snipped = sum(item.blocks_snipped for item in stats)
    action = "updated" if args.write else "would update"

    for item in stats:
        print(
            f"{item.path}: {item.blocks_snipped}/{item.blocks_seen} blocks {action}; "
            f"{item.original_bytes} -> {item.snipped_bytes} bytes "
            f"({item.bytes_saved} saved)"
        )

    print(f"Total: {total_snipped} blocks {action}; {total_saved} bytes saved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
