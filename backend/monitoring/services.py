import json
import logging
from datetime import timedelta

from django.utils import timezone

from commons.result import Err, Ok, Result
from monitoring.models import Link, Notification, Update
from monitoring.rate_limiter import DomainRateLimiter
from monitoring.strategies import STRATEGY_CHOICES, URL

logger = logging.getLogger(__name__)


def scrape_link(link: Link, rate_limiter: DomainRateLimiter | None = None) -> Result[int, str]:
	"""
	Scrape a single link. Returns Ok(update_count) or Err(error_message).
	"""
	if link.strategy is None:
		return Err("No strategy assigned")

	strategy_cls = STRATEGY_CHOICES.get(link.strategy.strat_cls)
	if strategy_cls is None:
		return Err(f"Unknown strategy class: {link.strategy.strat_cls}")

	strategy = strategy_cls()
	config_data = link.strategy.data or {}
	comparison_data = json.loads(link.comparison_info) if link.comparison_info else {}

	if rate_limiter is not None:
		rate_limiter.wait_for_domain(link.url)

	result, new_data = strategy.scrape(URL(link.url), config_data, comparison_data)

	match result:
		case Err(error=msg):
			logger.warning("Scrape failed for link %d (%s): %s", link.pk, link.url, msg)
			return Err(msg)
		case Ok(value=updates):
			created_count = 0
			cutoff = timezone.now() - timedelta(hours=24)
			# First scrape backfills the source's existing items as already-read so
			# the user isn't flooded with a backlog they never asked about. Only
			# items found on subsequent scrapes count as actual notifications.
			is_first_scrape = link.last_scraped is None
			notif_kwargs: dict = (
				{"status": Notification.Status.READ, "read_at": timezone.now()} if is_first_scrape else {}
			)

			for title, description, item_url in updates:
				# Deduplicate: skip if identical update exists within last 24h
				if Update.objects.filter(link=link, title=title, item_url=item_url, created_at__gte=cutoff).exists():
					continue

				update = Update.objects.create(
					link=link,
					title=title,
					description=description,
					item_url=item_url,
				)
				Notification.objects.create(update=update, **notif_kwargs)
				created_count += 1

			if new_data is not None:
				link.comparison_info = json.dumps(new_data)
			link.last_scraped = timezone.now()
			link.save()

			return Ok(created_count)

	return Err("Unexpected scrape_link")


def scrape_all_links(
	user_id: int | None = None,
	rate_limiter: DomainRateLimiter | None = None,
) -> dict[int, Result[int, str]]:
	"""
	Scrape all links (or all links for a specific user).
	Returns {link_id: result} dict.
	"""
	queryset = Link.objects.select_related("strategy")
	if user_id is not None:
		queryset = queryset.filter(user_id=user_id)

	limiter = rate_limiter if rate_limiter is not None else DomainRateLimiter()
	results: dict[int, Result[int, str]] = {}

	for link in queryset:
		results[link.pk] = scrape_link(link, limiter)

	return results
