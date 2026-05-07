from __future__ import annotations

from argparse import ArgumentParser
from typing import Any

from django.core.management.base import BaseCommand

from monitoring.rss_content_backfill import backfill_rss_update_content


class Command(BaseCommand):
	help = "Refresh existing RSS update descriptions from feed full-content bodies."

	def add_arguments(self, parser: ArgumentParser) -> None:
		parser.add_argument("--max-links", type=int, default=20, help="Maximum RSS links to backfill")
		parser.add_argument("--max-updates", type=int, default=500, help="Maximum existing updates to inspect")
		parser.add_argument("--start-after-link-id", type=int, default=0, help="Only process RSS links after this ID")
		parser.add_argument("--delay", type=float, default=2.0, help="Seconds between same-domain requests")

	def handle(self, *args: Any, **options: Any) -> None:
		summary = backfill_rss_update_content(
			max_links=options["max_links"],
			max_updates=options["max_updates"],
			start_after_link_pk=options["start_after_link_id"],
			delay=options["delay"],
		)
		self.stdout.write(
			"Done. "
			f"{summary.links_processed}/{summary.links_considered} RSS link(s), "
			f"{summary.updates_checked} update(s) checked, "
			f"{summary.updates_updated} description(s) updated, "
			f"{summary.fetch_errors} fetch error(s), "
			f"completed={summary.completed}."
		)
