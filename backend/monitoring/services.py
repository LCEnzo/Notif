import json
import logging
from datetime import timedelta
from json import JSONDecodeError

from django.utils import timezone

from commons.result import Err, Ok, Result
from monitoring.models import Link, Notification, Update
from monitoring.rate_limiter import DomainRateLimiter
from monitoring.strategies import STRATEGY_CHOICES, URL

logger = logging.getLogger(__name__)


def _comparison_data_for_link(link: Link) -> Result[dict, str]:
	if not link.comparison_info:
		return Ok({})
	try:
		data = json.loads(link.comparison_info)
	except JSONDecodeError as exc:
		logger.warning("Invalid comparison_info for link %d: %s", link.pk, exc)
		return Err("Stored comparison data is invalid; clear the link state before scraping again.")
	if not isinstance(data, dict):
		logger.warning("Invalid comparison_info shape for link %d: %s", link.pk, type(data).__name__)
		return Err("Stored comparison data is invalid; clear the link state before scraping again.")
	return Ok(data)


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
	comparison_result = _comparison_data_for_link(link)
	match comparison_result:
		case Err(error=msg):
			return Err(msg)
		case Ok(value=comparison_data):
			pass

	if rate_limiter is not None:
		rate_limiter.wait_for_domain(link.url)

	try:
		result = strategy.scrape(URL(link.url), config_data, comparison_data)
	except AssertionError:
		raise
	except Exception as exc:
		logger.exception("Scrape crashed for link %d (%s)", link.pk, link.url)
		return Err(f"Scrape failed unexpectedly: {exc}")

	match result:
		case Err(error=msg):
			logger.warning("Scrape failed for link %d (%s): %s", link.pk, link.url, msg)
			return Err(msg)
		case Ok(value=scrape):
			updates = scrape.updates
			new_data = scrape.comparison_state_update
			assert new_data is None or isinstance(new_data, dict), "strategy comparison state updates must be dicts"

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

	logger.error(
		"Strategy %s returned unexpected scrape result type %s for link %d (%s)",
		strategy_cls.__name__,
		type(result).__name__,
		link.pk,
		link.url,
	)
	return Err("Unexpected scrape result")


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
