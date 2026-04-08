import datetime
import os
import random
import shutil

from django.conf import settings
from faker import Faker
from faker.providers import bank, company, person

from accounts.models import User
from monitoring.models import Link, Strategy

# Global password variable for ease of access
password: str = 'password'

# This class is created to step around the issue that multi locale and
# multi provider use of the classes causes a NotImplementedException as of Faker 18.9.0
class MultiLocaleFaker:
	def __init__(self, locales):
		self._fakers = [Faker(locale) for locale in locales]
		for faker in self._fakers:
			faker.add_provider(company)
			faker.add_provider(bank)
			faker.add_provider(person)

	def __getattr__(self, name):
		return getattr(random.choice(self._fakers), name)

Faker.seed(0)
locales = ['it_IT', 'en_US', 'ja_JP', 'sk_SK']
faker = MultiLocaleFaker(locales)


def backup_db() -> None:
	"""
	Creates a backup of the DB, made for dev env thus works on/with sqlite.
	"""
	if settings.DATABASES.get('default', None) and settings.DATABASES['default'].get('NAME', None):
		db_file = settings.DATABASES['default']['NAME']
		backup_file = f"{db_file}.backup.{datetime.datetime.now(tz=datetime.UTC).strftime('%Y_%m_%d - %H %M %S')}"

		# copy the original database file to a new file
		shutil.copy2(db_file, backup_file)
		print(f"{os.path.exists(backup_file)}")
	else:
		print("Can't backup the DB, this function was made to work with SQLite.")
		print(f"Check the {backup_db.__name__} function in the {__file__} file.")


def create_users(user_count: int = 30) -> list[User]:
	existing_usernames = set(User.objects.values_list('username', flat=True))
	users = []

	for _ in range(user_count):
		# Generate a unique username
		username = faker.user_name()
		while username in existing_usernames:
			username = faker.user_name()

		existing_usernames.add(username)

		user = User.objects.create_user(
			username=username,
			email=faker.email(),
			password=password,
			name=faker.first_name() + " " + faker.last_name()
		)
		user.set_password(password)
		user.save()

		users.append(user)

	return users


def create_admin() -> User:
	user_list = create_users(1)
	user = user_list[0]

	user.is_staff = True
	user.is_superuser = True
	user.save()

	return user


def create_strat_and_links(user: User) -> tuple[Strategy, list[Link]]:
	assert user is not None and user.__class__ == User

	strat = Strategy.objects.create(strat_cls="GeneralSelectorStrategy", data={"selectors": ["body"]})
	link1 = Link.objects.create(
		name = "Google",
		url = "www.google.com",
		user = user,
		strategy = strat
	)
	link2 = Link.objects.create(
		name = "Bing",
		url = "bing.com",
		user = user,
		strategy = strat
	)

	return (strat, [link1, link2])
