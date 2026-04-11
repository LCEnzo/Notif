import logging
import os
from pprint import pprint  # noqa: F401

import requests
import requests_mock
from django.db.models import Model
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from commons.result import Err, Ok
from commons.test_utils import SetupMixin, ViewSetMixin, login_client
from monitoring.models import Link, Notification, Update
from monitoring.strategies import URL, GeneralSelectorStrategy, SBSVThreadmarksStrategy

logger = logging.getLogger(__name__)


class ResultTypeTestCase(TestCase):
	def test_ok_basic(self):
		r = Ok(42)
		assert r.is_ok()
		assert not r.is_err()
		assert r.unwrap() == 42
		assert r.unwrap_or(0) == 42

	def test_err_basic(self):
		r = Err("fail")
		assert not r.is_ok()
		assert r.is_err()
		assert r.unwrap_err() == "fail"
		assert r.unwrap_or(99) == 99

	def test_ok_unwrap_err_raises(self):
		with self.assertRaises(ValueError):
			Ok(1).unwrap_err()

	def test_err_unwrap_raises(self):
		with self.assertRaises(ValueError):
			Err("bad").unwrap()

	def test_ok_map(self):
		r = Ok(5).map(lambda x: x * 2)
		assert isinstance(r, Ok)
		assert r.unwrap() == 10

	def test_err_map_is_noop(self):
		r = Err("fail").map(lambda x: x * 2)
		assert isinstance(r, Err)
		assert r.unwrap_err() == "fail"

	def test_ok_map_err_is_noop(self):
		r = Ok(5).map_err(lambda e: e.upper())
		assert isinstance(r, Ok)
		assert r.unwrap() == 5

	def test_err_map_err(self):
		r = Err("fail").map_err(lambda e: e.upper())
		assert isinstance(r, Err)
		assert r.unwrap_err() == "FAIL"

	def test_ok_and_then(self):
		r: Ok[int] | Err[str] = Ok(5).and_then(lambda x: Ok(x + 1))
		assert isinstance(r, Ok)
		assert r.unwrap() == 6

	def test_ok_and_then_to_err(self):
		r: Ok[int] | Err[str] = Ok(5).and_then(lambda x: Err("nope"))
		assert isinstance(r, Err)

	def test_err_and_then_is_noop(self):
		r = Err("fail").and_then(lambda x: Ok(x + 1))
		assert isinstance(r, Err)
		assert r.unwrap_err() == "fail"

	def test_match_ok(self):
		match Ok(42):
			case Ok(value=v):
				assert v == 42
			case _:
				self.fail("Should have matched Ok")

	def test_match_err(self):
		match Err("bad"):
			case Err(error=e):
				assert e == "bad"
			case _:
				self.fail("Should have matched Err")


class TestSelectorStratErr(TestCase):
	def test_empty_html_returns_err(self):
		strat = GeneralSelectorStrategy()
		url = "https://example.com"
		config_data = {"selectors": ["div.content"]}

		with requests_mock.Mocker() as mocker:
			mocker.get(url, status_code=404)
			result, new_data = strat(URL(url), config_data, {})

		assert isinstance(result, Err)
		assert new_data is None

	def test_timeout_returns_err(self):
		strat = GeneralSelectorStrategy()
		url = "https://example.com"
		config_data = {"selectors": ["div.content"]}

		with requests_mock.Mocker() as mocker:
			mocker.get(url, exc=requests.exceptions.ConnectTimeout)
			result, new_data = strat(URL(url), config_data, {})

		assert isinstance(result, Err)
		assert new_data is None

	def test_sbsv_timeout_returns_err(self):
		strat = SBSVThreadmarksStrategy()
		url = URL("http://forums.spacebattles.com/threads/test.123/threadmarks")

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, exc=requests.exceptions.ReadTimeout)
			result, new_data = strat.scrape(url, {}, {'last_alert': ''})

		assert isinstance(result, Err)
		assert "Request failed" in result.error


class RateLimiterTestCase(TestCase):
	def test_same_domain_waits(self):
		from monitoring.rate_limiter import DomainRateLimiter
		limiter = DomainRateLimiter(delay=0.15)
		import time
		start = time.monotonic()
		limiter.wait_for_domain("https://example.com/a")
		limiter.wait_for_domain("https://example.com/b")
		elapsed = time.monotonic() - start
		assert elapsed >= 0.14

	def test_different_domains_no_wait(self):
		from monitoring.rate_limiter import DomainRateLimiter
		limiter = DomainRateLimiter(delay=0.5)
		import time
		start = time.monotonic()
		limiter.wait_for_domain("https://example.com/a")
		limiter.wait_for_domain("https://other.com/b")
		elapsed = time.monotonic() - start
		assert elapsed < 0.2


class TestSelectorStrat(TestCase):
	def test_selector_strat(self):
		strat = GeneralSelectorStrategy()

		url = "https://kemono.party/patreon/user/50187986"
		config_data = { "selectors": ["article.post-card"] }
		old_data: dict[str, list[int]] = {}
		html_content = """
		<html>
			<body>
				<article class="post-card">Post 1</article>
			</body>
		</html>
		"""

		with requests_mock.Mocker() as mocker:
			mocker.get(url, text=html_content)
			notif_data, new_data = strat(URL(url), config_data, old_data)

		logger.debug(
			"selector strat on kemono: \t" +
			f"{notif_data = } \n--------------------------\n" +
			f"{new_data = }\n--------------------------\n"
		)

		assert isinstance(notif_data, Ok)
		assert len(notif_data.value) > 0
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
			assert isinstance(updates, Ok)
			assert len(updates.value) >= 2


class LinkViewSetTestCase(ViewSetMixin):
	def setUp(
			self,
			list_view_name: str = "links-list",
			detail_view_name: str = "links-detail",
			model: type[Model] = Link,
			obj: Model | None = None,
		) -> None:
		super().setUp(
			list_view_name=list_view_name,
			detail_view_name=detail_view_name,
			model=model,
			obj=obj or self.links[0],
		)

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

	def test_get_strat_choices(self):
		response = self.api_client.get(reverse('get-strat-choices'))

		self.assertEqual(response.status_code, 200)
		self.assertTrue(isinstance(response.data, list))
		self.assertGreater(len(response.data), 0)

	def test_update_link(self):
		self._test_update_object()

	def test_delete_link(self):
		self._test_delete_object(create_fields={
			"name": "Disposable link",
			"url": "https://example.com/disposable",
			"user": f"{self.regular_user.pk}",
			"strategy": self.strat.pk,
		})

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


class NotificationViewSetTestCase(SetupMixin, TestCase):
	def setUp(self):
		# Create an Update and Notification for regular_user's first link
		self.update = Update.objects.create(
			link=self.links[0],
			title="New chapter posted",
			description="Chapter 42 is out",
			item_url="https://example.com/chapter-42",
		)
		self.notification = Notification.objects.create(update=self.update)

		# Create one for secondary_user's link too
		secondary_link = Link.objects.filter(user=self.secondary_user).first()
		assert secondary_link is not None
		other_update = Update.objects.create(
			link=secondary_link,
			title="Other user's update",
			description="Not yours",
			item_url="https://example.com/other",
		)
		self.other_notification = Notification.objects.create(update=other_update)

	def test_list_returns_only_own_notifications(self):
		response = self.api_client.get(reverse('notifications-list'))
		self.assertEqual(response.status_code, 200)
		ids = [n['id'] for n in response.data]
		self.assertIn(self.notification.pk, ids)
		self.assertNotIn(self.other_notification.pk, ids)

	def test_filter_by_status(self):
		response = self.api_client.get(reverse('notifications-list'), {'status': 'unread'})
		self.assertEqual(response.status_code, 200)
		self.assertEqual(len(response.data), 1)

		# Mark it read, then filter again
		self.api_client.patch(
			reverse('notifications-detail', kwargs={'pk': self.notification.pk}),
			{'status': 'read'},
			format='json',
		)
		response = self.api_client.get(reverse('notifications-list'), {'status': 'unread'})
		self.assertEqual(len(response.data), 0)

	def test_patch_mark_as_read_sets_read_at(self):
		response = self.api_client.patch(
			reverse('notifications-detail', kwargs={'pk': self.notification.pk}),
			{'status': 'read'},
			format='json',
		)
		self.assertEqual(response.status_code, 200)
		self.notification.refresh_from_db()
		self.assertEqual(self.notification.status, Notification.Status.READ)
		self.assertIsNotNone(self.notification.read_at)

	def test_other_user_cannot_access(self):
		other_client = login_client(APIClient(), self.secondary_user.get_username())
		response = other_client.get(
			reverse('notifications-detail', kwargs={'pk': self.notification.pk})
		)
		self.assertEqual(response.status_code, 404)

	def test_mark_all_read(self):
		# Create a second notification for regular_user
		update2 = Update.objects.create(
			link=self.links[0], title="Another update", item_url="https://example.com/2",
		)
		Notification.objects.create(update=update2)

		response = self.api_client.post(reverse('notifications-mark-all-read'))
		self.assertEqual(response.status_code, 200)
		self.assertEqual(response.data['marked_read'], 2)

		unread_count = Notification.objects.filter(
			update__link__user=self.regular_user, status=Notification.Status.UNREAD
		).count()
		self.assertEqual(unread_count, 0)
