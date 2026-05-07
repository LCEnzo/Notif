from __future__ import annotations

from dataclasses import dataclass

from commons.result import Err, Ok
from monitoring.models import Link, Update
from monitoring.rate_limiter import DomainRateLimiter
from monitoring.strategies import URL, FeedStrategy


@dataclass(frozen=True, slots=True)
class RssContentBackfillSummary:
	links_considered: int = 0
	links_processed: int = 0
	updates_checked: int = 0
	updates_updated: int = 0
	fetch_errors: int = 0
	last_link_pk: int | None = None
	completed: bool = False


def backfill_rss_update_content(
	*,
	max_links: int,
	max_updates: int,
	start_after_link_pk: int = 0,
	delay: float = 2.0,
) -> RssContentBackfillSummary:
	"""Refresh existing RSS update descriptions from full feed content."""
	max_links = max(0, max_links)
	max_updates = max(0, max_updates)
	start_after_link_pk = max(0, start_after_link_pk)
	delay = max(0.0, delay)

	if max_links == 0 or max_updates == 0:
		return RssContentBackfillSummary(completed=False)

	links = list(
		Link.objects.select_related("strategy")
		.filter(scrape_disabled=False, strategy__strat_cls="FeedStrategy", pk__gt=start_after_link_pk)
		.filter(updates__isnull=False)
		.distinct()
		.order_by("pk")[:max_links]
	)
	if not links:
		return RssContentBackfillSummary(completed=True)

	strategy = FeedStrategy()
	rate_limiter = DomainRateLimiter(delay=delay)
	updates_checked = 0
	updates_updated = 0
	fetch_errors = 0
	links_processed = 0
	last_processed_link_pk: int | None = None

	for link in links:
		if updates_checked >= max_updates:
			break

		last_processed_link_pk = link.pk
		rate_limiter.wait_for_domain(link.url)
		result = strategy.scrape(URL(link.url), {}, {})
		match result:
			case Err():
				fetch_errors += 1
				links_processed += 1
				continue
			case Ok(value=scrape):
				feed_updates = scrape.updates

		by_url = {str(update.item_url): update for update in feed_updates if str(update.item_url)}
		by_title = {update.title: update for update in feed_updates}
		existing_updates = Update.objects.filter(link=link).order_by("pk")

		for existing in existing_updates:
			updates_checked += 1
			scraped = by_url.get(existing.item_url) if existing.item_url else None
			if scraped is None:
				scraped = by_title.get(existing.title)
			if scraped is None or not scraped.description:
				continue
			if existing.description == scraped.description:
				continue

			existing.description = scraped.description
			existing.save(update_fields=["description"])
			updates_updated += 1

		links_processed += 1

	return RssContentBackfillSummary(
		links_considered=len(links),
		links_processed=links_processed,
		updates_checked=updates_checked,
		updates_updated=updates_updated,
		fetch_errors=fetch_errors,
		last_link_pk=last_processed_link_pk,
		completed=links_processed == len(links) and len(links) < max_links,
	)
