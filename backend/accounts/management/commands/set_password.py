from argparse import ArgumentParser
from typing import Any

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from accounts.models import RefreshSessionFamily, User
from accounts.refresh_sessions import revoke_all_refresh_families_for_user


class Command(BaseCommand):
	help = "Set a user's password from the command line (recovery for locked-out users)."

	def add_arguments(self, parser: ArgumentParser) -> None:
		parser.add_argument("username", type=str, help="Username to reset password for")
		parser.add_argument("--password", type=str, help="New password (omit for interactive prompt)")

	def handle(self, *args: Any, **options: Any) -> None:
		username = options["username"]
		try:
			user = User._base_manager.get(username=username)
		except User.DoesNotExist:
			raise CommandError(f"User '{username}' does not exist") from None

		password = options.get("password")
		if password is None:
			import getpass

			password = getpass.getpass("New password: ")
			confirm = getpass.getpass("Confirm password: ")
			if password != confirm:
				raise CommandError("Passwords do not match")
			if not password.strip():
				raise CommandError("Password cannot be empty")

		try:
			validate_password(password, user)
		except ValidationError as exc:
			raise CommandError("\n".join(str(e) for e in exc.messages)) from exc

		# Recovery assumes the account may be compromised, so every session
		# goes - unlike an authenticated change, there is no session here that
		# has proven anything.
		with transaction.atomic():
			user.set_password(password)
			user.save(update_fields=["password", "date_modified"])
			revoked = revoke_all_refresh_families_for_user(
				user, reason=RefreshSessionFamily.RevokeReason.PASSWORD_CHANGE
			)
		self.stdout.write(self.style.SUCCESS(f"Password set for '{username}', {revoked} session(s) revoked"))
