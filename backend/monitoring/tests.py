import logging

from django.test import TestCase

from monitoring.strategies import URL, GeneralSelectorStrategy

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