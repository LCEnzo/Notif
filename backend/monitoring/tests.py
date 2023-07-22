import logging
import os
from pprint import pprint  # noqa: F401

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
			f"{notif_data = } \n--------------------------\n" + 
			f"{new_data = }\n--------------------------\n"
		)

		assert type(notif_data) != str
		assert new_data is not None


class SBSVThreadmarksStrategyTestCase(TestCase):
	def setUp(self):
		self.url = URL('http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1')
		self.strategy = SBSVThreadmarksStrategy()

	def test_scrape(self):
		file_path = f'{os.path.dirname(__file__)}/tests/skkitterdoc-threadmarks.html'
		with open(file_path) as html_file, requests_mock.Mocker() as mocker:
			html_content = html_file.read()
			mocker.get(self.url, text=html_content)

			updates, new_data = self.strategy.scrape(self.url, {}, {'last_alert': '2023-06-08T15:30:00+0000'})
			
			assert new_data is not None
			assert ('last_alert' in new_data)
			assert updates is not None
			assert len(updates) == 2


