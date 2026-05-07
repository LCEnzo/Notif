from __future__ import annotations

import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from time import monotonic
from typing import Any

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from accounts.models.password_reset import (
	PASSWORD_RESET_CODE_MAX_ATTEMPTS,
	PASSWORD_RESET_CODE_TTL,
	PasswordResetCode,
)
from commons.result import Err, Ok
from monitoring.models import Link
from monitoring.rate_limiter import DomainRateLimiter
from monitoring.services import scrape_link
from ops.models import MaintenanceLock, SystemEvent

logger = logging.getLogger(__name__)

_LOCK_KEY = "run_due_tasks"
_MAX_FAILURE_BACKOFF_MINUTES = 24 * 60


class Command(BaseCommand):
	help = "Run bounded backend maintenance: cleanup, due scrapes, and future scheduled work."

	def add_arguments(self, parser: ArgumentParser) -> None:
		parser.add_argument("--max-links", type=int, default=20, help="Maximum due links to scrape in one run")
		parser.add_argument("--max-runtime-seconds", type=int, default=240, help="Maximum runtime before stopping")
		parser.add_argument("--delay", type=float, default=2.0, help="Seconds between same-domain requests")
		parser.add_argument(
			"--lock-ttl-seconds", type=int, default=30 * 60, help="Seconds before a stale lock is ignored"
		)

	def handle(self, *args: Any, **options: Any) -> None:
		max_links = max(0, options["max_links"])
		max_runtime_seconds = max(1, options["max_runtime_seconds"])
		delay = max(0.0, options["delay"])
		lock_ttl_seconds = max(1, options["lock_ttl_seconds"])

		if lock_ttl_seconds < max_runtime_seconds:
			logger.warning(
				"lock-ttl-seconds (%d) < max-runtime-seconds (%d); raising lock TTL to %d",
				lock_ttl_seconds,
				max_runtime_seconds,
				max_runtime_seconds,
			)
			lock_ttl_seconds = max_runtime_seconds

		lock_acquired_at = _acquire_lock(lock_ttl_seconds)
		if lock_acquired_at is None:
			self.stdout.write("Skipped: maintenance lock is already held.")
			return

		started = monotonic()
		now = timezone.now()
		summary = {
			"password_reset_codes_deleted": 0,
			"links_considered": 0,
			"scrape_ok": 0,
			"scrape_error": 0,
			"updates_found": 0,
		}

		try:
			summary["password_reset_codes_deleted"] = _cleanup_password_reset_codes(now)
			links = _due_links(now, max_links)
			summary["links_considered"] = len(links)
			rate_limiter = DomainRateLimiter(delay=delay)

			for link in links:
				if monotonic() - started >= max_runtime_seconds:
					break

				result = scrape_link(link, rate_limiter)
				match result:
					case Ok(value=count):
						summary["scrape_ok"] += 1
						summary["updates_found"] += count
						_record_scrape_success(link)
						if count > 0:
							self.stdout.write(f"Link {link.pk}: {count} new update(s)")
					case Err(error=message):
						summary["scrape_error"] += 1
						_record_scrape_failure(link, message)
						self.stderr.write(f"Link {link.pk}: error — {message}")

			SystemEvent.objects.create(
				level=SystemEvent.Level.INFO,
				source="ops.run_due_tasks",
				kind="maintenance",
				message=(
					"Maintenance finished: "
					f"{summary['scrape_ok']} scrape(s) ok, "
					f"{summary['scrape_error']} error(s), "
					f"{summary['password_reset_codes_deleted']} reset code(s) deleted."
				),
				details=summary,
			)
			self.stdout.write(
				"Done. "
				f"{summary['scrape_ok']} scrape(s) ok, "
				f"{summary['scrape_error']} error(s), "
				f"{summary['updates_found']} update(s), "
				f"{summary['password_reset_codes_deleted']} reset code(s) deleted."
			)
		finally:
			_release_lock(lock_acquired_at)


def _acquire_lock(lock_ttl_seconds: int) -> datetime | None:
	now = timezone.now()
	stale_before = now - timedelta(seconds=lock_ttl_seconds)
	with transaction.atomic():
		lock = MaintenanceLock.objects.filter(key=_LOCK_KEY).first()
		if lock is not None and lock.acquired_at > stale_before:
			return None
		MaintenanceLock.objects.update_or_create(key=_LOCK_KEY, defaults={"acquired_at": now})
		return now


def _release_lock(acquired_at: datetime) -> None:
	MaintenanceLock.objects.filter(key=_LOCK_KEY, acquired_at=acquired_at).delete()


def _cleanup_password_reset_codes(now: datetime) -> int:
	expired_before = now - PASSWORD_RESET_CODE_TTL
	deleted, _ = PasswordResetCode.objects.filter(
		Q(created_at__lt=expired_before) | Q(failed_attempts__gte=PASSWORD_RESET_CODE_MAX_ATTEMPTS)
	).delete()
	return deleted


def _due_links(now: datetime, max_links: int) -> list[Link]:
	if max_links <= 0:
		return []
	return list(
		Link.objects.select_related("strategy")
		.filter(scrape_disabled=False)
		.filter(Q(next_scrape_at__isnull=True) | Q(next_scrape_at__lte=now))
		.order_by("next_scrape_at", "pk")[:max_links]
	)


def _record_scrape_success(link: Link) -> None:
	link.scrape_failure_count = 0
	link.last_scrape_error = ""
	link.next_scrape_at = timezone.now() + timedelta(minutes=link.scrape_interval_minutes)
	link.save(update_fields=["scrape_failure_count", "last_scrape_error", "next_scrape_at"])


def _record_scrape_failure(link: Link, message: str) -> None:
	failure_count = min(link.scrape_failure_count + 1, 30)
	backoff_minutes = min(
		link.scrape_interval_minutes * (2 ** max(0, failure_count - 1)),
		_MAX_FAILURE_BACKOFF_MINUTES,
	)
	link.scrape_failure_count = failure_count
	link.last_scrape_error = message[:500]
	link.next_scrape_at = timezone.now() + timedelta(minutes=backoff_minutes)
	link.save(update_fields=["scrape_failure_count", "last_scrape_error", "next_scrape_at"])
