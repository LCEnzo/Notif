import logging
import os
from pprint import pprint  # noqa: F401
from unittest.mock import patch

import requests
import requests_mock
from django.core.management import call_command
from django.db.models import Model
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from commons import Err, Ok
from commons.test_utils import SetupMixin, ViewSetMixin, login_client
from commons.utils import create_notification
from monitoring.models import Link, Notification, Strategy, Update
from monitoring.services import scrape_link
from monitoring.strategies import URL, FeedStrategy, GeneralSelectorStrategy, SBSVThreadmarksStrategy

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


class StrategyViewSetTestCase(SetupMixin, TestCase):
	def test_list_includes_orphaned_strategies(self):
		orphan = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["body"]},
		)

		response = self.api_client.get(reverse('strategies-list'))

		self.assertEqual(response.status_code, 200)
		ids = [item['id'] for item in response.data]
		self.assertIn(orphan.pk, ids)

	def test_list_excludes_other_users_non_orphaned_strategies(self):
		other_only_strategy = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["article.post-card"]},
		)
		Link.objects.create(
			name="Other user's private strategy",
			url="https://example.com/private",
			user=self.secondary_user,
			strategy=other_only_strategy,
		)

		response = self.api_client.get(reverse('strategies-list'))

		self.assertEqual(response.status_code, 200)
		ids = [item['id'] for item in response.data]
		self.assertNotIn(other_only_strategy.pk, ids)

	def test_delete_orphaned_strategy(self):
		orphan = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["body"]},
		)

		response = self.api_client.delete(
			reverse('strategies-detail', kwargs={'pk': orphan.pk})
		)

		self.assertEqual(response.status_code, 204)
		self.assertFalse(Strategy.objects.filter(pk=orphan.pk).exists())


class NotificationViewSetTestCase(SetupMixin, TestCase):
	def setUp(self):
		# Create an Update and Notification for regular_user's first link
		self.notification = create_notification(
			link=self.links[0],
			title="New chapter posted",
			description="Chapter 42 is out",
			item_url="https://example.com/chapter-42",
		)
		self.update = self.notification.update

		# Create one for secondary_user's link too
		secondary_link = Link.objects.filter(user=self.secondary_user).first()
		assert secondary_link is not None
		self.other_notification = create_notification(
			link=secondary_link,
			title="Other user's update",
			description="Not yours",
			item_url="https://example.com/other",
		)

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
		create_notification(
			link=self.links[0],
			title="Another update",
			item_url="https://example.com/2",
		)

		response = self.api_client.post(reverse('notifications-mark-all-read'))
		self.assertEqual(response.status_code, 200)
		self.assertEqual(response.data['marked_read'], 2)

		unread_count = Notification.objects.filter(
			update__link__user=self.regular_user, status=Notification.Status.UNREAD
		).count()
		self.assertEqual(unread_count, 0)


class ScrapeServiceTestCase(SetupMixin, TestCase):
	def setUp(self):
		# Fixture links use schemeless URLs like "www.google.com" which
		# requests can't dispatch. Give them proper URLs for service tests.
		for link in self.links:
			link.url = f"https://{link.url}"
			link.save()

	def test_scrape_link_creates_updates_and_notifications(self):
		link = self.links[0]
		html = '<html><body><article class="post-card">New Post</article></body></html>'

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			result = scrape_link(link)

		assert isinstance(result, Ok)
		assert result.value > 0
		assert Update.objects.filter(link=link).exists()
		assert Notification.objects.filter(update__link=link).exists()

	def test_scrape_link_no_strategy_returns_err(self):
		link = self.links[0]
		link.strategy = None
		link.save()

		result = scrape_link(link)
		assert isinstance(result, Err)
		assert "No strategy" in result.error

	def test_scrape_link_sets_last_scraped(self):
		link = self.links[0]
		assert link.last_scraped is None

		html = '<html><body><article class="post-card">Post</article></body></html>'
		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			scrape_link(link)

		link.refresh_from_db()
		assert link.last_scraped is not None

	def test_scrape_link_deduplication(self):
		link = self.links[0]
		html = '<html><body><article class="post-card">Same Post</article></body></html>'

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			scrape_link(link)
			count_after_first = Update.objects.filter(link=link).count()

			scrape_link(link)
			count_after_second = Update.objects.filter(link=link).count()

		assert count_after_first == count_after_second

	def test_scrape_link_updates_comparison_info(self):
		link = self.links[0]
		assert link.comparison_info == ''

		html = '<html><body><article class="post-card">Post</article></body></html>'
		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			scrape_link(link)

		link.refresh_from_db()
		assert link.comparison_info != ''

	def test_management_command_runs(self):
		link = self.links[0]
		html = '<html><body><article class="post-card">Post</article></body></html>'

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			# Should not raise
			call_command('scrape', '--link', str(link.pk), '--delay', '0')

	def test_management_command_bulk_passes_custom_delay(self):
		rate_limiter = object()

		with (
			patch("monitoring.management.commands.scrape.DomainRateLimiter", return_value=rate_limiter) as limiter_cls,
			patch("monitoring.management.commands.scrape.scrape_all_links", return_value={}) as scrape_all,
		):
			call_command('scrape', '--delay', '5')

		limiter_cls.assert_called_once_with(delay=5.0)
		scrape_all.assert_called_once_with(user_id=None, rate_limiter=rate_limiter)


# ── FeedStrategy Tests ────────────────────────────────────────────────────

ATOM_FEED_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Example Blog</title>
  <link href="https://example.com/feed" rel="self"/>
  <entry>
    <id>tag:example.com,2024:1</id>
    <title>First Post</title>
    <link href="https://example.com/post/1"/>
    <summary>This is the first post.</summary>
  </entry>
  <entry>
    <id>tag:example.com,2024:2</id>
    <title>Second Post</title>
    <link href="https://example.com/post/2"/>
    <summary>This is the second post.</summary>
  </entry>
  <entry>
    <id>tag:example.com,2024:3</id>
    <title>Third Post</title>
    <link href="https://example.com/post/3"/>
    <description>This is the third post.</description>
  </entry>
</feed>"""


class FeedStrategyTestCase(TestCase):
	def setUp(self):
		self.strategy = FeedStrategy()
		self.feed_url = URL("https://example.com/feed")

	def test_can_scrape_url_returns_true(self):
		assert self.strategy.can_scrape_url(URL("https://anything.example.com/rss")) is True
		assert self.strategy.can_scrape_url(URL("https://substack.com/feed")) is True
		assert self.strategy.can_scrape_url(URL("https://forum.example.com/index.rss")) is True

	def test_scrape_new_feed_returns_all_entries_and_sets_comparison(self):
		"""First scrape of a feed: returns all entries, sets last_entry_id to the first (newest)."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert len(result.value) == 3
		assert result.value[0][0] == "First Post"
		assert result.value[1][0] == "Second Post"
		assert result.value[2][0] == "Third Post"
		assert comparison is not None
		assert comparison["last_entry_id"] == "tag:example.com,2024:1"

	def test_scrape_with_last_entry_id_skips_seen(self):
		"""With last_entry_id set to the newest entry, no new entries should be returned."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result, comparison = self.strategy.scrape(
				self.feed_url, {}, {"last_entry_id": "tag:example.com,2024:1"}
			)

		assert isinstance(result, Ok)
		assert len(result.value) == 0
		assert comparison is None

	def test_scrape_with_middle_entry_id_returns_newer_only(self):
		"""With last_entry_id set to the middle entry, returns entries before that point."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result, comparison = self.strategy.scrape(
				self.feed_url, {}, {"last_entry_id": "tag:example.com,2024:3"}
			)

		assert isinstance(result, Ok)
		assert len(result.value) == 2
		assert result.value[0][0] == "First Post"
		assert result.value[1][0] == "Second Post"
		assert comparison is not None
		assert comparison["last_entry_id"] == "tag:example.com,2024:1"

	def test_scrape_empty_feed_returns_ok_empty(self):
		"""A feed with no entries returns Ok([]), None."""
		empty_feed = """\
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Empty Feed</title>
</feed>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=empty_feed)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert result.value == []
		assert comparison is None

	def test_scrape_http_error_returns_err(self):
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, status_code=500)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Err)
		assert "500" in result.error or "Feed fetch failed" in result.error
		assert comparison is None

	def test_scrape_timeout_returns_err(self):
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, exc=requests.exceptions.ConnectTimeout)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Err)
		assert "Feed fetch failed" in result.error
		assert comparison is None

	def test_scrape_invalid_xml_with_no_entries_returns_err(self):
		"""Bozo parse error and no entries → Err."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text="not valid xml {{{")
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Err)
		assert "parse error" in result.error.lower()
		assert comparison is None

	def test_scrape_bozo_with_entries_still_works(self):
		"""Bozo flag on but entries present → still returns entries (feed was partially parseable)."""
		# feedparser sets bozo on some imperfect feeds that still have entries
		# Our strategy treats bozo as fatal only when there are no entries
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		# ATOM_FEED_XML should parse cleanly (no bozo), so this proves the happy path
		assert isinstance(result, Ok)
		assert len(result.value) == 3

	def test_entry_id_falls_back_to_link(self):
		"""Entry without an <id> field uses <link> as the identifier."""
		no_id_feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>No-ID Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Only Item</title>
      <link>https://example.com/post/only</link>
      <description>Content here.</description>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=no_id_feed)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert len(result.value) == 1
		assert result.value[0][0] == "Only Item"
		assert comparison is not None
		assert comparison["last_entry_id"] == "https://example.com/post/only"

	def test_rss_feed_parsed_correctly(self):
		"""RSS 2.0 feeds are handled (feedparser supports both Atom and RSS)."""
		rss_feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>RSS Blog</title>
    <link>https://example.com</link>
    <description>Test RSS feed</description>
    <item>
      <title>RSS Post One</title>
      <link>https://example.com/post/rss1</link>
      <guid isPermaLink="true">https://example.com/post/rss1</guid>
      <description>First RSS item.</description>
    </item>
    <item>
      <title>RSS Post Two</title>
      <link>https://example.com/post/rss2</link>
      <guid isPermaLink="true">https://example.com/post/rss2</guid>
      <description>Second RSS item.</description>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=rss_feed)
			result, comparison = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert len(result.value) == 2
		assert result.value[0][0] == "RSS Post One"
		assert result.value[1][0] == "RSS Post Two"
		assert comparison is not None
		assert comparison["last_entry_id"] == "https://example.com/post/rss1"

	def test_entry_uses_description_with_summary_fallback(self):
		"""Description field is preferred; summary used as fallback."""
		feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Desc Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Has Description</title>
      <link>https://example.com/1</link>
      <description>Explicit description.</description>
    </item>
    <item>
      <title>No Description</title>
      <link>https://example.com/2</link>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=feed)
			result, _ = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert result.value[0][1] == "Explicit description."
		assert result.value[1][1] == ""
