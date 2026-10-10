"""Write one CSV per record type for a profile; health.export holds the logic."""

from argparse import ArgumentParser
from datetime import date
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.core.management.base import BaseCommand, CommandError

from accounts.models import User
from health.export import ExportSpec, Profile, export
from health.models import RecordType


def _types(raw: str) -> tuple[RecordType, ...]:
	if raw == "all":
		return tuple(RecordType)
	names = [name.strip() for name in raw.split(",") if name.strip()]
	unknown = sorted(set(names) - set(RecordType.values))
	if unknown or not names:
		raise CommandError(f"Unknown types {unknown or [raw]}; choose 'all' or from {sorted(RecordType.values)}.")
	return tuple(RecordType(name) for name in dict.fromkeys(names))


def _date(raw: str | None, option: str) -> date | None:
	try:
		return None if raw is None else date.fromisoformat(raw)
	except ValueError as exc:
		raise CommandError(f"{option} must be a date such as 2026-10-08, not {raw!r}.") from exc


class Command(BaseCommand):
	help = "Export a user's Health Connect data: one long-format CSV per record type."

	def add_arguments(self, parser: ArgumentParser) -> None:
		parser.add_argument("--user", required=True, help="Username whose data to export.")
		parser.add_argument("--profile", required=True, choices=[profile.value for profile in Profile])
		parser.add_argument("--types", default="all", help="'all', or a comma list of record types.")
		parser.add_argument("--start", help="First local date to include, YYYY-MM-DD.")
		parser.add_argument("--end", help="Last local date to include, YYYY-MM-DD.")
		parser.add_argument("--tz", default="Europe/Belgrade", help="IANA zone for local dates and times.")
		parser.add_argument("--output-dir", required=True, type=Path)

	def handle(self, *args: Any, **options: Any) -> None:
		owner = User.objects.filter(username=options["user"]).first()
		if owner is None:
			raise CommandError(f"No user named {options['user']!r}.")
		try:
			tz = ZoneInfo(options["tz"])
		except (ZoneInfoNotFoundError, ValueError) as exc:
			raise CommandError(f"Unknown time zone {options['tz']!r}.") from exc
		spec = ExportSpec(
			owner_id=owner.pk,
			profile=Profile(options["profile"]),
			types=_types(options["types"]),
			tz=tz,
			output_dir=options["output_dir"],
			start=_date(options["start"], "--start"),
			end=_date(options["end"], "--end"),
		)
		try:
			written = export(spec)
		except ValueError as exc:
			raise CommandError(str(exc)) from exc
		for path, rows in written:
			self.stdout.write(f"{path}: {rows} rows")
