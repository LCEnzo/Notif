from typing import IO, Any

class FeedParserDict(dict[str, Any]):
	entries: list[dict[str, Any]]
	bozo: bool
	bozo_exception: BaseException | None

# The real parse also takes bytes or str, and opens either as a local path or a
# URL when it names one. Only a stream is typed here, so fetched data cannot be
# passed in a form that feedparser might open.
def parse(data: IO[bytes]) -> FeedParserDict: ...
