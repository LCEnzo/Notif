from pathlib import Path

import requests

thread_url = "https://forums.sufficientvelocity.com/threads/skitterdoc-2077.109765/"
response = requests.get(thread_url)
with Path("skkitterdoc.html").open("xb") as f:
	f.write(response.content)

threadmarks_url = "https://forums.sufficientvelocity.com/threads/skitterdoc-2077.109765/threadmarks-load-range?threadmark_category_id=1"
response = requests.get(threadmarks_url)
with Path("skkitterdoc-threadmarks.html").open("xb") as f:
	f.write(response.content)
