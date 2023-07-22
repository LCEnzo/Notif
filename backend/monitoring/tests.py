import logging

import requests_mock
from django.test import TestCase

from monitoring.strategies import URL, GeneralSelectorStrategy, SBSVThreadmarksStrategy

logger = logging.getLogger(__name__)


class TestSelectorStrat(TestCase):
	def test_selector_strat(self):
		strat = GeneralSelectorStrategy()

		url = "https://kemono.party/patreon/user/50187986" 
		config_data = { "selectors": ["article.post-card"] }
		old_data = {}
		
		notif_data, new_data = strat(URL(url), config_data, old_data)
		
		logger.debug(
			"selector strat on kemono: \t" + 
			f"{notif_data} \n--------------------------\n" + 
			f"{new_data}\n--------------------------\n"
		)

		assert type(notif_data) != str
		assert new_data is not None


class SBSVThreadmarksStrategyTestCase(TestCase):
	def setUp(self):
		self.url = "https://forums.sufficientvelocity.com/threads/skitterdoc-2077.109765/"
		self.strategy = SBSVThreadmarksStrategy()

	def test_scrape(self, m):
		with open('tests/skkitterdoc-threadmarks.html', 'r') as html_file, requests_mock.Mocker() as mocker:
			html_content = html_file.read()
			mocker.get(self.url, text=html_content)

			updates, new_data = self.strategy.scrape(URL(self.url), {}, {'last_alert': '2023-07-08T15:30:00+0000'})

		# Mock the requests.get method
		with requests_mock.Mocker() as m:
			# When this URL is requested, respond with the contents of index.html
			m.get('http://example.com', text=html_content)
		
		# -------

		url = URL('http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1')
		m.get(url, text='mocked response') # replace with actual mocked response

		# test when last_alert is not None
		updates, new_data = self.strategy.scrape(url, {}, {'last_alert': '2023-07-08T15:30:00+0000'})

		# Assert that updates and new_data are as expected
		# ... (write your assertions here)

		# test when last_alert is None
		updates, new_data = self.strategy.scrape(url, {}, {})

		# Assert that updates and new_data are as expected
		# ... (write your assertions here)


class SBSVThreadmarksStrategyTest(TestCase):
	def setUp(self):
		self.url = "https://forums.sufficientvelocity.com/threads/skitterdoc-2077.109765/"
		self.strategy = SBSVThreadmarksStrategy()
		
		with open("./tests/skitterdoc-threadmarks.html") as f:
			self.mock_response = f.read()

	@requests_mock.Mocker()
	def test_scrape(self, mock_req):
		mock_req.get(self.url, text=self.mock_response)

		# assuming some default configuration and comparison data
		config_data = {}
		comparison_data = {}
		
		updates, new_data = self.strategy.scrape(URL(self.url), config_data, comparison_data)

		from pprint import pprint

		pprint("updates: ", updates)
		pprint("new_data: ", new_data)

		# Here, you can add asserts to check if the results are as expected.
		# This will heavily depend on your mocked response and what kind of updates you expect.


