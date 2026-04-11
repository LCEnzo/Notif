from django.core.management.base import BaseCommand

from commons.result import Err, Ok
from monitoring.models import Link
from monitoring.rate_limiter import DomainRateLimiter
from monitoring.services import scrape_all_links, scrape_link


class Command(BaseCommand):
	help = "Scrape all monitored links for updates."

	def add_arguments(self, parser):
		parser.add_argument("--user", type=int, help="Only scrape links for this user ID")
		parser.add_argument("--link", type=int, help="Only scrape this specific link ID")
		parser.add_argument("--delay", type=float, default=2.0, help="Seconds between same-domain requests")

	def handle(self, *args, **options):
		if options["link"]:
			try:
				link = Link.objects.select_related("strategy").get(pk=options["link"])
			except Link.DoesNotExist:
				self.stderr.write(f"Link {options['link']} not found")
				return

			rate_limiter = DomainRateLimiter(delay=options["delay"])
			result = scrape_link(link, rate_limiter)
			match result:
				case Ok(value=count):
					self.stdout.write(f"Link {link.pk}: {count} new update(s)")
				case Err(error=msg):
					self.stderr.write(f"Link {link.pk}: error — {msg}")
		else:
			results = scrape_all_links(user_id=options.get("user"))
			ok_count = 0
			err_count = 0
			total_updates = 0

			for link_id, result in results.items():
				match result:
					case Ok(value=count):
						ok_count += 1
						total_updates += count
						if count > 0:
							self.stdout.write(f"  Link {link_id}: {count} new update(s)")
					case Err(error=msg):
						err_count += 1
						self.stderr.write(f"  Link {link_id}: error — {msg}")

			self.stdout.write(
				f"Done. {ok_count} succeeded, {err_count} failed, {total_updates} total new update(s)."
			)
