import requests

thread_url = "https://forums.sufficientvelocity.com/threads/skitterdoc-2077.109765/"
response = requests.get(thread_url)
with open("skkitterdoc.html", 'xb') as f:
	f.write(response.content)

threadmarks_url = "https://forums.sufficientvelocity.com/threads/skitterdoc-2077.109765/threadmarks-load-range?threadmark_category_id=1"
response = requests.get(threadmarks_url)
with open("skkitterdoc-threadmarks.html", 'xb') as f:
	f.write(response.content)

