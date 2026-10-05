from typing import IO, Any

class FeedParserDict(dict[str, Any]):
	entries: list[dict[str, Any]]
	bozo: bool
	bozo_exception: BaseException | None

# The real parse also takes bytes or str: it opens either one as a local file
# when it names one, and fetches a str that carries a URL scheme. Only a stream
# is typed here, so fetched data cannot be passed in a form that feedparser
# might open or fetch.
def parse(data: IO[bytes], /) -> FeedParserDict: ...
