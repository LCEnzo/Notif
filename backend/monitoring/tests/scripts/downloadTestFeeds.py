from pathlib import Path

import requests

feeds = {
	"citriniresearch": "https://www.citriniresearch.com/feed",
	"semianalysis": "https://semianalysis.com/feed",
	"astralcodexten": "https://www.astralcodexten.com/feed",
	"sufficientvelocity": "https://forums.sufficientvelocity.com/forums/-/index.rss",
	"stratechery": "https://stratechery.com/feed",
}

for name, url in feeds.items():
	response = requests.get(url, timeout=15)
	response.raise_for_status()
	with Path(f"{name}.xml").open("xb") as f:
		f.write(response.content)
	print(f"{name}.xml — {len(response.content)} bytes, {response.status_code}")  # noqa: T201
