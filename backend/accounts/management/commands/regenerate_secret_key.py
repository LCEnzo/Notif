from pathlib import Path

from django.core.management.base import BaseCommand
from django.core.management.utils import get_random_secret_key
from dotenv import load_dotenv, set_key


class Command(BaseCommand):
	help = "Regenerates the DJANGO_SECRET_KEY in the .env file."

	def handle(self, *args, **kwargs):
		# get the path to the .env file
		env_path = Path(".env")

		# load the .env file
		load_dotenv(dotenv_path=env_path)

		# generate a new secret key
		new_secret_key = get_random_secret_key()

		# set the new secret key in the .env file
		set_key(env_path, "DJANGO_SECRET_KEY", new_secret_key)

		self.stdout.write(self.style.SUCCESS("Successfully updated DJANGO_SECRET_KEY."))
