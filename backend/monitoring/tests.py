import hashlib
import logging
import xml.sax.saxutils
from pathlib import Path
from pprint import pprint  # noqa: F401
from typing import Any, cast
from unittest.mock import patch

import pytest
import requests
import requests_mock
from django.core.management import call_command
from django.db.models import Model
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from hypothesis import given, settings
from hypothesis import strategies as st
from hypothesis.extra.django import TestCase as HypothesisTestCase
from rest_framework.test import APIClient

from commons import Err, Ok
from commons.test_utils import SetupMixin, ViewSetMixin, login_client
from commons.utils import create_notification
from monitoring.models import Link, Notification, Strategy, Update
from monitoring.rss_content_backfill import backfill_rss_update_content
from monitoring.services import scrape_link
from monitoring.strategies import (
	STRATEGY_CHOICES,
	URL,
	BaseStrategy,
	FeedStrategy,
	GeneralSelectorStrategy,
	SBSVThreadmarksStrategy,
	ScrapeResult,
	ScrapeSuccess,
)

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
			result = strat(URL(url), config_data, {})

		assert isinstance(result, Err)

	def test_timeout_returns_err(self):
		strat = GeneralSelectorStrategy()
		url = "https://example.com"
		config_data = {"selectors": ["div.content"]}

		with requests_mock.Mocker() as mocker:
			mocker.get(url, exc=requests.exceptions.ConnectTimeout)
			result = strat(URL(url), config_data, {})

		assert isinstance(result, Err)

	def test_sbsv_timeout_returns_err(self):
		strat = SBSVThreadmarksStrategy()
		url = URL("http://forums.spacebattles.com/threads/test.123/threadmarks")

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, exc=requests.exceptions.ReadTimeout)
			result = strat.scrape(url, {}, {"last_alert": ""})

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
		config_data = {"selectors": ["article.post-card"]}
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
			result = strat(URL(url), config_data, old_data)

		logger.debug("selector strat on kemono: \\t" + f"{result = } \n--------------------------\n")

		assert isinstance(result, Ok)
		assert len(result.value.updates) > 0
		assert result.value.comparison_state_update is not None


class SBSVThreadmarksStrategyTestCase(TestCase):
	def setUp(self):
		self.url = URL(
			"http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1"
		)
		self.strategy = SBSVThreadmarksStrategy()

	@pytest.mark.slow
	@pytest.mark.e2e
	def test_scrape(self):
		file_path = Path(__file__).parent / "tests" / "skkitterdoc-threadmarks.html"
		with file_path.open() as html_file, requests_mock.Mocker() as mocker:
			html_content = html_file.read()
			mocker.get(self.url, text=html_content)

			result = self.strategy.scrape(self.url, {}, {"last_alert": "2023-06-08T15:30:00+0000"})

			assert isinstance(result, Ok)
			new_data = result.value.comparison_state_update
			assert new_data is not None
			assert "last_alert" in new_data
			assert len(result.value.updates) >= 2


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
			"strategy": self.strat.pk,
		}
		resp = self._test_create_object(fields=fields)  # noqa: F841
		# print(f"{resp = }")
		# print(f"{resp.content!r}")

	def test_get_strat_choices(self):
		response = self.api_client.get(reverse("get-strat-choices"))

		self.assertEqual(response.status_code, 200)
		self.assertTrue(isinstance(response.data, list))
		self.assertGreater(len(response.data), 0)

	def test_links_list_is_paginated(self):
		response = self.api_client.get(reverse("links-list"))
		self.assertEqual(response.status_code, 200)
		self.assertEqual(set(response.data.keys()), {"count", "next", "previous", "results"})
		self.assertIsNone(response.data["next"])  # fixture has < 100 links

	def test_links_list_respects_page_size(self):
		response = self.api_client.get(reverse("links-list"), {"page_size": 1})
		self.assertEqual(response.status_code, 200)
		self.assertEqual(len(response.data["results"]), 1)
		self.assertGreater(response.data["count"], 1)
		self.assertIsNotNone(response.data["next"])

	def test_update_link(self):
		self._test_update_object()

	def test_delete_link(self):
		self._test_delete_object(
			create_fields={
				"name": "Disposable link",
				"url": "https://example.com/disposable",
				"user": f"{self.regular_user.pk}",
				"strategy": self.strat.pk,
			}
		)

	def test_regular_link_permissions(self):
		fields = {
			"name": "Skitterdoc on Spacebattles",
			"url": "http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1",
			"user": f"{self.regular_user.pk}",
			"strategy": self.strat.pk,
		}
		update_fields = {"name": "Maria"}
		permissions = {"list": True, "retrieve": True, "create": True, "update": True, "delete": True}
		self._test_permissions(
			user=self.regular_user,
			obj_pk=self.links[0].pk,
			fields=fields,
			update_fields=update_fields,
			permissions=permissions,
		)

	def test_other_user_link_permissions(self):
		fields = {
			"name": "Skitterdoc on Spacebattles",
			"url": "http://forums.spacebattles.com/threads/some-thread.1234567/threadmarks-load-range?threadmark_category_id=1",
			"user": f"{self.regular_user.pk}",
			"strategy": self.strat.pk,
		}
		update_fields = {"name": "Maria"}
		permissions = {"list": True, "retrieve": False, "create": True, "update": False, "delete": False}
		_ = self._test_permissions(
			user=self.secondary_user,
			obj_pk=self.links[0].pk,
			fields=fields,
			update_fields=update_fields,
			permissions=permissions,
		)


class StrategyViewSetTestCase(SetupMixin, TestCase):
	def test_list_includes_orphaned_strategies(self):
		orphan = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["body"]},
		)

		response = self.api_client.get(reverse("strategies-list"))

		self.assertEqual(response.status_code, 200)
		ids = [item["id"] for item in response.data]
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

		response = self.api_client.get(reverse("strategies-list"))

		self.assertEqual(response.status_code, 200)
		ids = [item["id"] for item in response.data]
		self.assertNotIn(other_only_strategy.pk, ids)

	def test_delete_orphaned_strategy(self):
		orphan = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["body"]},
		)

		response = self.api_client.delete(reverse("strategies-detail", kwargs={"pk": orphan.pk}))

		self.assertEqual(response.status_code, 204)
		self.assertFalse(Strategy.objects.filter(pk=orphan.pk).exists())

	def test_delete_strategy_still_in_use(self):
		"""Deleting a strategy with active links returns 400."""
		response = self.api_client.delete(reverse("strategies-detail", kwargs={"pk": self.strat.pk}))
		self.assertEqual(response.status_code, 400)
		self.assertTrue(Strategy.objects.filter(pk=self.strat.pk).exists())


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
		response = self.api_client.get(reverse("notifications-list"))
		self.assertEqual(response.status_code, 200)
		self.assertIn("results", response.data)
		ids = [n["id"] for n in response.data["results"]]
		self.assertIn(self.notification.pk, ids)
		self.assertNotIn(self.other_notification.pk, ids)

	def test_list_response_is_paginated(self):
		response = self.api_client.get(reverse("notifications-list"))
		self.assertEqual(response.status_code, 200)
		self.assertEqual(set(response.data.keys()), {"count", "next", "previous", "unread_count", "results"})

	def test_envelope_unread_count_is_global_not_filtered(self):
		# Add a read notification so the user has 1 unread + 1 read total.
		create_notification(
			link=self.links[0],
			title="Read one",
			item_url="https://example.com/read-one",
			status=Notification.Status.READ,
			read_at=timezone.now(),
		)
		# Filter the listing to status=read; the envelope's unread_count should
		# still report the user's actual unread total (1), not 0.
		response = self.api_client.get(reverse("notifications-list"), {"status": "read"})
		self.assertEqual(response.status_code, 200)
		self.assertEqual(len(response.data["results"]), 1)
		self.assertEqual(response.data["unread_count"], 1)

	def test_pagination_respects_page_size(self):
		# Existing setUp creates one regular_user notification; add 2 more so we
		# have 3 total, then request page_size=2 to force a second page.
		for i in range(2):
			create_notification(link=self.links[0], title=f"Extra {i}", item_url=f"https://example.com/extra/{i}")
		response = self.api_client.get(reverse("notifications-list"), {"page_size": 2})
		self.assertEqual(response.status_code, 200)
		self.assertEqual(response.data["count"], 3)
		self.assertEqual(len(response.data["results"]), 2)
		self.assertIsNotNone(response.data["next"])

	def test_filter_by_status(self):
		response = self.api_client.get(reverse("notifications-list"), {"status": "unread"})
		self.assertEqual(response.status_code, 200)
		self.assertEqual(len(response.data["results"]), 1)

		# Mark it read, then filter again
		self.api_client.patch(
			reverse("notifications-detail", kwargs={"pk": self.notification.pk}),
			{"status": "read"},
			format="json",
		)
		response = self.api_client.get(reverse("notifications-list"), {"status": "unread"})
		self.assertEqual(len(response.data["results"]), 0)

	def test_patch_mark_as_read_sets_read_at(self):
		response = self.api_client.patch(
			reverse("notifications-detail", kwargs={"pk": self.notification.pk}),
			{"status": "read"},
			format="json",
		)
		self.assertEqual(response.status_code, 200)
		self.notification.refresh_from_db()
		self.assertEqual(self.notification.status, Notification.Status.READ)
		self.assertIsNotNone(self.notification.read_at)

	def test_patch_mark_as_unread_clears_read_at(self):
		self.notification.status = Notification.Status.READ
		self.notification.read_at = timezone.now()
		self.notification.save()

		response = self.api_client.patch(
			reverse("notifications-detail", kwargs={"pk": self.notification.pk}),
			{"status": "unread"},
			format="json",
		)
		self.assertEqual(response.status_code, 200)
		self.notification.refresh_from_db()
		self.assertEqual(self.notification.status, Notification.Status.UNREAD)
		self.assertIsNone(self.notification.read_at)

	def test_other_user_cannot_access(self):
		other_client = login_client(APIClient(), self.secondary_user.get_username())
		response = other_client.get(reverse("notifications-detail", kwargs={"pk": self.notification.pk}))
		self.assertEqual(response.status_code, 404)

	def test_mark_all_read(self):
		# Create a second notification for regular_user
		create_notification(
			link=self.links[0],
			title="Another update",
			item_url="https://example.com/2",
		)

		response = self.api_client.post(reverse("notifications-mark-all-read"))
		self.assertEqual(response.status_code, 200)
		self.assertEqual(response.data["marked_read"], 2)

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

	def test_first_scrape_marks_notifications_read(self):
		# Fresh link: last_scraped is None until the first scrape completes,
		# so any items found are treated as backlog and stored as already-read.
		link = self.links[0]
		assert link.last_scraped is None
		html = '<html><body><article class="post-card">Backlog item</article></body></html>'

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			scrape_link(link)

		notifications = Notification.objects.filter(update__link=link)
		assert notifications.exists()
		for notification in notifications:
			assert notification.status == Notification.Status.READ
			assert notification.read_at is not None

	def test_subsequent_scrape_marks_notifications_unread(self):
		# Simulate a link that's been scraped before by pre-setting last_scraped.
		# Items found on this scrape should arrive as UNREAD, not READ.
		link = self.links[0]
		link.last_scraped = timezone.now()
		link.save()
		html = '<html><body><article class="post-card">Item</article></body></html>'

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			scrape_link(link)

		notifications = Notification.objects.filter(update__link=link)
		assert notifications.exists()
		for notification in notifications:
			assert notification.status == Notification.Status.UNREAD
			assert notification.read_at is None

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
		assert link.comparison_info == ""

		html = '<html><body><article class="post-card">Post</article></body></html>'
		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			scrape_link(link)

		link.refresh_from_db()
		assert link.comparison_info != ""

	def test_scrape_link_invalid_comparison_info_returns_err(self):
		link = self.links[0]
		link.comparison_info = "not-json"
		link.save(update_fields=["comparison_info"])

		html = '<html><body><article class="post-card">Post</article></body></html>'
		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			result = scrape_link(link)

		assert isinstance(result, Err)
		assert "Stored comparison data is invalid" in result.error
		assert not Update.objects.filter(link=link).exists()

	def test_scrape_link_strategy_crash_returns_logged_err(self):
		class RaisingStrategy(BaseStrategy):
			display_name = "Raising"

			def can_scrape_url(self, url: URL) -> bool:
				return True

			def scrape(
				self, url: URL, config_data: dict[str, Any], comparison_data: dict[str, Any], *args, **kwargs
			) -> ScrapeResult:
				raise RuntimeError("boom")

		link = self.links[0]
		link.strategy = Strategy.objects.create(strat_cls="RaisingStrategy", data={})
		link.save(update_fields=["strategy"])

		with (
			patch.dict(STRATEGY_CHOICES, {"RaisingStrategy": RaisingStrategy}),
			self.assertLogs("monitoring.services", level="ERROR") as logs,
		):
			result = scrape_link(link)

		assert isinstance(result, Err)
		assert result.error == "Scrape failed unexpectedly: boom"
		assert any("Scrape crashed for link" in message for message in logs.output)

	def test_scrape_link_invalid_comparison_update_returns_logged_err(self):
		class InvalidComparisonStateStrategy(BaseStrategy):
			display_name = "Invalid comparison state"

			def can_scrape_url(self, url: URL) -> bool:
				return True

			def scrape(
				self, url: URL, config_data: dict[str, Any], comparison_data: dict[str, Any], *args, **kwargs
			) -> ScrapeResult:
				return Ok(ScrapeSuccess(updates=[], comparison_state_update=cast(Any, [])))

		link = self.links[0]
		link.strategy = Strategy.objects.create(strat_cls="InvalidComparisonStateStrategy", data={})
		link.save(update_fields=["strategy"])

		with (
			patch.dict(STRATEGY_CHOICES, {"InvalidComparisonStateStrategy": InvalidComparisonStateStrategy}),
			self.assertLogs("monitoring.services", level="ERROR") as logs,
		):
			result = scrape_link(link)

		assert isinstance(result, Err)
		assert result.error == "Strategy returned invalid comparison state."
		assert any("returned invalid comparison state type list" in message for message in logs.output)

	def test_scrape_link_invalid_scrape_result_returns_logged_err(self):
		class InvalidScrapeResultStrategy(BaseStrategy):
			display_name = "Invalid scrape result"

			def can_scrape_url(self, url: URL) -> bool:
				return True

			def scrape(
				self, url: URL, config_data: dict[str, Any], comparison_data: dict[str, Any], *args, **kwargs
			) -> ScrapeResult:
				return cast(ScrapeResult, "not a scrape result")

		link = self.links[0]
		link.strategy = Strategy.objects.create(strat_cls="InvalidScrapeResultStrategy", data={})
		link.save(update_fields=["strategy"])

		with (
			patch.dict(STRATEGY_CHOICES, {"InvalidScrapeResultStrategy": InvalidScrapeResultStrategy}),
			self.assertLogs("monitoring.services", level="ERROR") as logs,
		):
			result = scrape_link(link)

		assert isinstance(result, Err)
		assert result.error == "Unexpected scrape result"
		assert any("returned unexpected scrape result type str" in message for message in logs.output)

	def test_management_command_runs(self):
		link = self.links[0]
		html = '<html><body><article class="post-card">Post</article></body></html>'

		with requests_mock.Mocker() as mocker:
			mocker.get(requests_mock.ANY, text=html)
			# Should not raise
			call_command("scrape", "--link", str(link.pk), "--delay", "0")

	def test_management_command_bulk_passes_custom_delay(self):
		rate_limiter = object()

		with (
			patch("monitoring.management.commands.scrape.DomainRateLimiter", return_value=rate_limiter) as limiter_cls,
			patch("monitoring.management.commands.scrape.scrape_all_links", return_value={}) as scrape_all,
		):
			call_command("scrape", "--delay", "5")

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

	def _entry_hashes(self, *entry_ids: str) -> list[str]:
		return [self.strategy._entry_id_hash(entry_id) for entry_id in entry_ids]

	def test_can_scrape_url_returns_true(self):
		assert self.strategy.can_scrape_url(URL("https://anything.example.com/rss")) is True
		assert self.strategy.can_scrape_url(URL("https://substack.com/feed")) is True
		assert self.strategy.can_scrape_url(URL("https://forum.example.com/index.rss")) is True

	def test_scrape_new_feed_returns_all_entries_and_sets_comparison(self):
		"""First scrape of a feed: returns all entries, sets last_entry_id to the first (newest)."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		updates = result.value.updates
		comparison = result.value.comparison_state_update
		assert len(updates) == 3
		assert updates[0][0] == "First Post"
		assert updates[1][0] == "Second Post"
		assert updates[2][0] == "Third Post"
		assert comparison is not None
		assert comparison["last_entry_id"] == "tag:example.com,2024:1"
		assert comparison["seen_entry_hashes"] == self._entry_hashes(
			"tag:example.com,2024:1",
			"tag:example.com,2024:2",
			"tag:example.com,2024:3",
		)
		assert "seen_entry_ids" not in comparison

	def test_scrape_with_seen_entry_ids_skips_seen(self):
		"""Legacy raw seen_entry_ids state still suppresses previously seen entries."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result = self.strategy.scrape(
				self.feed_url,
				{},
				{
					"last_entry_id": "tag:example.com,2024:1",
					"seen_entry_ids": [
						"tag:example.com,2024:1",
						"tag:example.com,2024:2",
						"tag:example.com,2024:3",
					],
				},
			)

		assert isinstance(result, Ok)
		assert len(result.value.updates) == 0
		assert result.value.comparison_state_update is None

	def test_scrape_with_seen_entry_hashes_skips_seen(self):
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result = self.strategy.scrape(
				self.feed_url,
				{},
				{
					"last_entry_id": "tag:example.com,2024:1",
					"seen_entry_hashes": self._entry_hashes(
						"tag:example.com,2024:1",
						"tag:example.com,2024:2",
						"tag:example.com,2024:3",
					),
				},
			)

		assert isinstance(result, Ok)
		assert result.value.updates == []
		assert result.value.comparison_state_update is None

	def test_seen_entry_hashes_migrate_legacy_raw_ids(self):
		assert self.strategy._seen_entry_hashes(
			{"seen_entry_ids": ["https://example.com/post/1"]}
		) == self._entry_hashes("https://example.com/post/1")

	def test_seen_entry_hashes_are_bounded(self):
		original_limit = FeedStrategy.MAX_SEEN_ENTRY_HASHES
		try:
			FeedStrategy.MAX_SEEN_ENTRY_HASHES = 3
			assert FeedStrategy._merge_seen_entry_hashes(
				["current-1", "current-2", "current-3", "current-4"],
				["previous-1"],
			) == ["current-1", "current-2", "current-3"]
		finally:
			FeedStrategy.MAX_SEEN_ENTRY_HASHES = original_limit

	def test_scrape_with_middle_entry_id_returns_newer_only(self):
		"""With last_entry_id set to the middle entry, returns entries before that point."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=ATOM_FEED_XML)
			result = self.strategy.scrape(self.feed_url, {}, {"last_entry_id": "tag:example.com,2024:3"})

		assert isinstance(result, Ok)
		updates = result.value.updates
		comparison = result.value.comparison_state_update
		assert len(updates) == 2
		assert updates[0][0] == "First Post"
		assert updates[1][0] == "Second Post"
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
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert result.value.updates == []
		assert result.value.comparison_state_update is None

	def test_scrape_http_error_returns_err(self):
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, status_code=500)
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Err)
		assert "500" in result.error or "Feed fetch failed" in result.error

	def test_scrape_timeout_returns_err(self):
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, exc=requests.exceptions.ConnectTimeout)
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Err)
		assert "Feed fetch failed" in result.error

	def test_scrape_invalid_xml_with_no_entries_returns_err(self):
		"""Bozo parse error and no entries → Err."""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text="not valid xml {{{")
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Err)
		assert "parse error" in result.error.lower()

	def test_scrape_bozo_with_entries_still_works(self):
		"""Bozo flag on but entries present → still returns entries (feed was partially parseable)."""
		# Missing closing </channel> — feedparser sets bozo but still finds items
		half_broken_feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Broken Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Still Here</title>
      <link>https://example.com/post/1</link>
      <description>Found it.</description>
    </item>
"""
		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=half_broken_feed)
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert len(result.value.updates) == 1
		assert result.value.updates[0][0] == "Still Here"

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
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert len(result.value.updates) == 1
		assert result.value.updates[0][0] == "Only Item"
		comparison = result.value.comparison_state_update
		assert comparison is not None
		assert comparison["last_entry_id"] == "https://example.com/post/only"

	def test_entry_id_falls_back_to_stable_title_hash(self):
		entry_id = self.strategy._entry_id({"title": "Only title"})

		expected_digest = hashlib.sha256(b"Only title").hexdigest()
		assert entry_id == f"sha256:{expected_digest}"

	def test_scrape_detects_oldest_first_appended_entries(self):
		initial_feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Append Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Old Post</title>
      <link>https://example.com/post/old</link>
      <description>Already seen.</description>
    </item>
    <item>
      <title>Middle Post</title>
      <link>https://example.com/post/middle</link>
      <description>Already seen.</description>
    </item>
  </channel>
</rss>"""
		appended_feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Append Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Old Post</title>
      <link>https://example.com/post/old</link>
      <description>Already seen.</description>
    </item>
    <item>
      <title>Middle Post</title>
      <link>https://example.com/post/middle</link>
      <description>Already seen.</description>
    </item>
    <item>
      <title>New Post</title>
      <link>https://example.com/post/new</link>
      <description>Appended later.</description>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=initial_feed)
			result1 = self.strategy.scrape(self.feed_url, {}, {})
			assert isinstance(result1, Ok)
			comparison1 = result1.value.comparison_state_update
			assert comparison1 is not None
			mocker.get(self.feed_url, text=appended_feed)
			result2 = self.strategy.scrape(self.feed_url, {}, comparison1)

		assert comparison1["seen_entry_hashes"] == self._entry_hashes(
			"https://example.com/post/old",
			"https://example.com/post/middle",
		)

		assert isinstance(result2, Ok)
		assert result2.value.updates == [("New Post", "Appended later.", URL("https://example.com/post/new"))]
		comparison2 = result2.value.comparison_state_update
		assert comparison2 is not None
		assert comparison2["seen_entry_hashes"] == self._entry_hashes(
			"https://example.com/post/old",
			"https://example.com/post/middle",
			"https://example.com/post/new",
		)

	def test_scrape_migrates_legacy_last_entry_id_without_order_assumption(self):
		feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Legacy Append Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Old Post</title>
      <link>https://example.com/post/old</link>
      <description>Already seen.</description>
    </item>
    <item>
      <title>New Post</title>
      <link>https://example.com/post/new</link>
      <description>Appended later.</description>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=feed)
			result = self.strategy.scrape(
				self.feed_url,
				{},
				{"last_entry_id": "https://example.com/post/old"},
			)

		assert isinstance(result, Ok)
		assert result.value.updates == [("New Post", "Appended later.", URL("https://example.com/post/new"))]
		comparison = result.value.comparison_state_update
		assert comparison is not None
		assert comparison["seen_entry_hashes"] == self._entry_hashes(
			"https://example.com/post/old",
			"https://example.com/post/new",
		)

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
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert len(result.value.updates) == 2
		assert result.value.updates[0][0] == "RSS Post One"
		assert result.value.updates[1][0] == "RSS Post Two"
		comparison = result.value.comparison_state_update
		assert comparison is not None
		assert comparison["last_entry_id"] == "https://example.com/post/rss1"

	def test_entry_prefers_full_content_with_description_fallback(self):
		"""Full feed content is preferred; description and summary are fallbacks."""
		feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Desc Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Has Full Content</title>
      <link>https://example.com/1</link>
      <description>Short summary.</description>
      <content:encoded><![CDATA[
        <article>
          <h1>Full post heading</h1>
          <p>First paragraph with <a href="https://example.com">a link</a>.</p>
          <script>alert("nope")</script>
          <p>Second paragraph.</p>
        </article>
      ]]></content:encoded>
    </item>
    <item>
      <title>Has Description</title>
      <link>https://example.com/2</link>
      <description>Explicit description.</description>
    </item>
    <item>
      <title>No Description</title>
      <link>https://example.com/3</link>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get(self.feed_url, text=feed)
			result = self.strategy.scrape(self.feed_url, {}, {})

		assert isinstance(result, Ok)
		assert "Full post heading" in result.value.updates[0][1]
		assert "First paragraph with a link." in result.value.updates[0][1]
		assert "Second paragraph." in result.value.updates[0][1]
		assert "Short summary." not in result.value.updates[0][1]
		assert "alert" not in result.value.updates[0][1]
		assert result.value.updates[1][1] == "Explicit description."
		assert result.value.updates[2][1] == ""


# ── Real Feed Fixture Tests ——————————————————————————————————————————————
# These use downloaded feed XML files (see tests/scripts/downloadTestFeeds.py).
# Marked `slow` — skip with: pytest -m "not slow"


REAL_FEEDS = {
	"citriniresearch": "citriniresearch.xml",
	"semianalysis": "semianalysis.xml",
	"astralcodexten": "astralcodexten.xml",
	"sufficientvelocity": "sufficientvelocity.xml",
	"stratechery": "stratechery.xml",
}


class FeedStrategyRealFeedTestCase(TestCase):
	"""Tests FeedStrategy against real downloaded feed files."""

	def setUp(self):
		self.strategy = FeedStrategy()

	def _load_feed(self, filename: str) -> str:
		file_path = Path(__file__).parent / "tests" / filename
		with file_path.open(encoding="utf-8") as f:
			return f.read()

	@pytest.mark.slow
	@pytest.mark.feed
	@pytest.mark.e2e
	def test_all_real_feeds_parse_successfully(self):
		"""Every real feed file returns Ok with at least 1 entry."""
		for name, filename in REAL_FEEDS.items():
			with self.subTest(feed=name):
				xml = self._load_feed(filename)
				url = URL(f"https://{name}.example.com/feed")

				with requests_mock.Mocker() as mocker:
					mocker.get(url, text=xml)
					result = self.strategy.scrape(url, {}, {})

				assert isinstance(result, Ok), f"{name} returned Err: {result if hasattr(result, 'value') else result}"
				assert len(result.value.updates) > 0, f"{name} returned 0 entries"
				# Each entry must have title, description, url
				for entry in result.value.updates:
					assert len(entry) == 3
					assert entry[0], f"{name} entry has empty title"
					assert entry[2], f"{name} entry has empty url"

	@pytest.mark.slow
	@pytest.mark.feed
	@pytest.mark.e2e
	def test_real_feed_incremental_scraping(self):
		"""Incremental scraping works with a real feed: second scrape returns nothing new."""
		xml = self._load_feed("citriniresearch.xml")
		url = URL("https://example.com/feed")

		with requests_mock.Mocker() as mocker:
			mocker.get(url, text=xml)

			# First scrape — returns all entries
			result1 = self.strategy.scrape(url, {}, {})
			assert isinstance(result1, Ok)
			assert len(result1.value.updates) > 0
			comparison1 = result1.value.comparison_state_update
			assert comparison1 is not None
			assert "last_entry_id" in comparison1

			# Second scrape with comparison data — returns nothing
			result2 = self.strategy.scrape(url, {}, comparison1)
			assert isinstance(result2, Ok)
			assert len(result2.value.updates) == 0
			assert result2.value.comparison_state_update is None

	@pytest.mark.slow
	@pytest.mark.feed
	@pytest.mark.e2e
	def test_sufficientvelocity_rss_specifics(self):
		"""SV's RSS uses <guid> entries and cross-links — FeedStrategy handles them."""
		xml = self._load_feed("sufficientvelocity.xml")
		url = URL("https://forums.sufficientvelocity.com/forums/-/index.rss")

		with requests_mock.Mocker() as mocker:
			mocker.get(url, text=xml)
			result = self.strategy.scrape(url, {}, {})

		assert isinstance(result, Ok)
		# SV should have many items
		assert len(result.value.updates) >= 20, f"Expected >=20, got {len(result.value.updates)}"
		comparison = result.value.comparison_state_update
		assert comparison is not None


class RssContentBackfillTestCase(SetupMixin, TestCase):
	def test_backfill_updates_existing_rss_update_from_full_content(self):
		strategy = Strategy.objects.create(strat_cls="FeedStrategy", data={})
		link = Link.objects.create(
			name="RSS source",
			url="https://example.com/feed",
			user=self.regular_user,
			strategy=strategy,
		)
		update = Update.objects.create(
			link=link,
			title="Post One",
			description="Short summary.",
			item_url="https://example.com/post-one",
		)
		feed = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Example Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Post One</title>
      <link>https://example.com/post-one</link>
      <description>Short summary.</description>
      <content:encoded><![CDATA[
        <article>
          <p>Full body paragraph.</p>
          <p>Another useful paragraph.</p>
        </article>
      ]]></content:encoded>
    </item>
  </channel>
</rss>"""

		with requests_mock.Mocker() as mocker:
			mocker.get("https://example.com/feed", text=feed)
			summary = backfill_rss_update_content(max_links=10, max_updates=10, delay=0)

		update.refresh_from_db()
		self.assertEqual(summary.links_processed, 1)
		self.assertEqual(summary.updates_checked, 1)
		self.assertEqual(summary.updates_updated, 1)
		self.assertIn("Full body paragraph.", update.description)
		self.assertIn("Another useful paragraph.", update.description)
		self.assertNotEqual(update.description, "Short summary.")


# ── Property-Based Tests ————————————————————————————————————————————————
# These use Hypothesis to verify invariants across generated RSS and Atom feeds.

NL = "\n"


@st.composite
def _rss_item(draw):
	"""Generate a single RSS <item> with optional guid and description."""
	escape = xml.sax.saxutils.escape
	title = escape(draw(st.text(min_size=1, max_size=60)))
	link = escape(draw(st.text(min_size=3, max_size=100)))
	has_guid = draw(st.booleans())
	guid = escape(draw(st.text(min_size=1, max_size=60))) if has_guid else None
	has_desc = draw(st.booleans())
	desc = escape(draw(st.text(min_size=1, max_size=150))) if has_desc else None

	parts = [f"<title>{title}</title>", f"<link>{link}</link>"]
	if guid is not None:
		parts.append(f'<guid isPermaLink="false">{guid}</guid>')
	if desc is not None:
		parts.append(f"<description>{desc}</description>")

	nl = "\n"
	return "    <item>" + nl + "      " + nl.join(parts) + nl + "    </item>"


@st.composite
def _rss_feed_xml(draw, min_items=1, max_items=20):
	"""Generate a valid RSS 2.0 feed with randomized items."""
	n = draw(st.integers(min_value=min_items, max_value=max_items))
	items = draw(st.lists(_rss_item(), min_size=n, max_size=n))

	return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Hypothesis Test Feed</title>
    <link>https://example.com</link>
    <description>Auto-generated for property testing</description>
{NL.join(items)}
  </channel>
</rss>"""


@st.composite
def _atom_entry(draw):
	"""Generate a single Atom <entry> with optional summary."""
	escape = xml.sax.saxutils.escape
	eid = escape(draw(st.text(min_size=1, max_size=60)))
	title = escape(draw(st.text(min_size=1, max_size=60)))
	# quoteattr wraps in quotes and escapes " and ' — escape() alone doesn't
	# handle attribute-value quoting, which can produce invalid XML.
	link = xml.sax.saxutils.quoteattr(draw(st.text(min_size=3, max_size=100)))
	has_summary = draw(st.booleans())
	summary = escape(draw(st.text(min_size=1, max_size=150))) if has_summary else None

	parts = [
		f"<id>tag:example.com,2024:{eid}</id>",
		f"<title>{title}</title>",
		f"<link href={link}/>",
	]
	if summary is not None:
		parts.append(f"<summary>{summary}</summary>")

	nl = "\n"
	return "  <entry>" + nl + "    " + nl.join(parts) + nl + "  </entry>"


@st.composite
def _atom_feed_xml(draw, min_items=1, max_items=20):
	"""Generate a valid Atom 1.0 feed with randomized entries."""
	n = draw(st.integers(min_value=min_items, max_value=max_items))
	entries = draw(st.lists(_atom_entry(), min_size=n, max_size=n))

	return f"""<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Hypothesis Atom Feed</title>
  <link href="https://example.com/feed" rel="self"/>
{NL.join(entries)}
</feed>"""


class FeedStrategyDedupPropertyTestCase(HypothesisTestCase):
	"""Property-based tests for FeedStrategy dedup invariant."""

	def setUp(self):
		self.strategy = FeedStrategy()

	@pytest.mark.property
	@given(feed_xml=st.one_of(_rss_feed_xml(), _atom_feed_xml()))
	@settings(max_examples=200)
	def test_dedup_is_idempotent(self, feed_xml):
		"""Second scrape with first scrape's comparison data returns zero new entries."""
		url = URL("https://example.com/feed")

		with requests_mock.Mocker() as mocker:
			mocker.get(url, text=feed_xml)

			# First scrape
			result1 = self.strategy.scrape(url, {}, {})
			assert isinstance(result1, Ok), f"First scrape failed: {result1}"
			assert len(result1.value.updates) > 0, f"Feed has items but scrape returned 0. Feed: {feed_xml[:200]}..."
			comparison1 = result1.value.comparison_state_update
			assert comparison1 is not None

			# Second scrape with comparison data from first
			result2 = self.strategy.scrape(url, {}, comparison1)
			assert isinstance(result2, Ok), f"Second scrape failed: {result2}"
			assert len(result2.value.updates) == 0, (
				f"Dedup invariant violated: second scrape returned "
				f"{len(result2.value.updates)} entries. comparison1: {comparison1}"
			)
			assert result2.value.comparison_state_update is None, (
				f"Expected None comparison on dedup hit, got: {result2.value.comparison_state_update}"
			)
