"""Write one CSV per record type for a profile; health.export holds the logic."""

from argparse import ArgumentParser
from datetime import date
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.core.management.base import BaseCommand, CommandError

from accounts.models import User
from health.export import ExportSpec, Format, Profile, export
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
	if raw is None:
		return None
	try:
		return date.fromisoformat(raw)
	except ValueError as exc:
		raise CommandError(f"{option} must be a date such as 2026-10-08, not {raw!r}.") from exc


class Command(BaseCommand):
	help = "Export a user's Health Connect data: one long-format file per record type."

	def add_arguments(self, parser: ArgumentParser) -> None:
		parser.add_argument("--user", required=True, help="Username whose data to export.")
		parser.add_argument("--profile", required=True, choices=[profile.value for profile in Profile])
		parser.add_argument("--types", default="all", help="'all', or a comma list of record types.")
		parser.add_argument("--format", default=Format.CSV.value, choices=[fmt.value for fmt in Format])
		parser.add_argument("--start", help="First local date to include, YYYY-MM-DD.")
		parser.add_argument("--end", help="Last local date to include, YYYY-MM-DD.")
		parser.add_argument("--tz", default="Europe/Belgrade", help="IANA zone for local dates and times.")
		parser.add_argument("--output-dir", required=True, type=Path)

	def handle(self, *args: Any, **options: Any) -> None:
		try:
			owner = User.objects.get(username=options["user"])
		except User.DoesNotExist as exc:
			raise CommandError(f"No user named {options['user']!r}.") from exc
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
			format=Format(options["format"]),
		)
		try:
			files = export(spec)
		except ValueError as exc:
			raise CommandError(str(exc)) from exc
		for exported in files:
			self.stdout.write(f"{exported.path}: {exported.rows} rows")
