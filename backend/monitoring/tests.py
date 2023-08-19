import logging
import os
from pprint import pprint  # noqa: F401

import requests_mock
from django.test import TestCase

from commons.test_utils import ViewSetMixin
from monitoring.models import Link
from monitoring.strategies import URL, GeneralSelectorStrategy, SBSVThreadmarksStrategy

logger = logging.getLogger(__name__)


class TestSelectorStrat(TestCase):
	def test_selector_strat(self):
		strat = GeneralSelectorStrategy()

		url = "https://kemono.party/patreon/user/50187986" 
		config_data = { "selectors": ["article.post-card"] }
		old_data: dict[str, list[int]] = {}
		
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
			assert len(updates) >= 2


class LinkViewSetTestCase(ViewSetMixin):
	def setUp(self):
		# TODO, have some initialization, so there are instances of Link and Strat in the DB
		super().setUp(list_view_name = "links-list", detail_view_name = "links-detail", model=Link)

	def test_list_links(self):
		filters = {"user__pk": f"{self.regular_user.pk}"}
		self._test_list_objects(filters=filters)

	def test_retrieve_link(self):
		self._test_retrieve_object(comparison_field="url")

	def test_create_link(self):
		fields = {
			"name": "Skitterdoc on Spacebattles", 
			"url": "http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1", 
			"user": f"{self.regular_user.pk}",
			"strategy": self.strat.pk
		}
		resp = self._test_create_object(fields=fields)  # noqa: F841
		# print(f"{resp = }")
		# print(f"{resp.content!r}")

	def test_update_link(self):
		self._test_update_object()

	def test_delete_link(self):
		self._test_delete_object()

	def test_regular_link_permissions(self):
		fields = {
			"name": "Skitterdoc on Spacebattles", 
			"url": "http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1", 
			"user": f"{self.regular_user.pk}",
			"strategy": self.strat.pk
		}
		update_fields = {"name": "Maria"}
		permissions = {'list': True, 'retrieve': True, 'create': True, 'update': True, 'delete': True}
		self._test_permissions(
			user=self.regular_user,
			obj_pk=self.links[0].pk,
			fields=fields, 
			update_fields=update_fields, 
			permissions=permissions
		)

	def test_other_user_link_permissions(self):
		fields = {
			"name": "Skitterdoc on Spacebattles", 
			"url": "http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1", 
			"user": f"{self.regular_user.pk}",
			"strategy": self.strat.pk
		}
		update_fields = {"name": "Maria"}
		permissions = {'list': True, 'retrieve': False, 'create': True, 'update': False, 'delete': False}
		_ = self._test_permissions(
			user=self.secondary_user,
			obj_pk=self.links[0].pk,
			fields=fields, 
			update_fields=update_fields, 
			permissions=permissions
		) 



