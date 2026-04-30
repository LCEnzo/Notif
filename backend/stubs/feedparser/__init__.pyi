from typing import Any

class FeedParserDict(dict[str, Any]):
	entries: list[dict[str, Any]]
	bozo: bool
	bozo_exception: BaseException | None


def parse(data: bytes | str) -> FeedParserDict: ...
