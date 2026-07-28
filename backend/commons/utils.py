import datetime
import logging
import random
from collections.abc import Sequence
from typing import Any

from faker import Faker
from faker.providers import bank, company, person

from accounts.models import User
from monitoring.models import Link, Notification, Strategy, Update

logger = logging.getLogger(__name__)

# Global password variable for ease of access
password: str = "password"


# This class is created to step around the issue that multi locale and
# multi provider use of the classes causes a NotImplementedException as of Faker 18.9.0
class MultiLocaleFaker:
	def __init__(self, locales: Sequence[str]) -> None:
		self._fakers = [Faker(locale) for locale in locales]
		for faker in self._fakers:
			faker.add_provider(company)
			faker.add_provider(bank)
			faker.add_provider(person)

	def __getattr__(self, name: str) -> Any:
		return getattr(random.choice(self._fakers), name)


Faker.seed(0)
locales = ["it_IT", "en_US", "ja_JP", "sk_SK"]
faker = MultiLocaleFaker(locales)


def create_users(user_count: int = 30) -> list[User]:
	existing_usernames = set(User.objects.values_list("username", flat=True))
	existing_emails = set(User.objects.values_list("email", flat=True))
	users = []

	for _ in range(user_count):
		# Generate a unique username
		username = faker.user_name()
		while username in existing_usernames:
			username = faker.user_name()

		existing_usernames.add(username)

		# User.email is unique=True, but faker draws from finite locale pools,
		# so a batch of 30 collides often enough to flake CI depending on the
		# pytest-randomly seed. Bounded retries, then force uniqueness.
		email = faker.email()
		for _attempt in range(20):
			if email not in existing_emails:
				break
			email = faker.email()
		if email in existing_emails:
			local, _, domain = email.partition("@")
			email = f"{local}+{len(existing_emails)}@{domain}"

		existing_emails.add(email)

		user = User.objects.create_user(
			username=username, email=email, password=password, name=faker.first_name() + " " + faker.last_name()
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
	link1 = Link.objects.create(name="Google", url="www.google.com", user=user, strategy=strat)
	link2 = Link.objects.create(name="Bing", url="bing.com", user=user, strategy=strat)

	return (strat, [link1, link2])


def create_update(
	link: Link,
	title: str = "New update",
	description: str = "",
	item_url: str = "https://example.com/update",
) -> Update:
	return Update.objects.create(
		link=link,
		title=title,
		description=description,
		item_url=item_url,
	)


def create_notification(
	update: Update | None = None,
	*,
	link: Link | None = None,
	title: str = "New update",
	description: str = "",
	item_url: str = "https://example.com/update",
	status: str = Notification.Status.UNREAD,
	read_at: datetime.datetime | None = None,
) -> Notification:
	if update is None:
		assert link is not None
		update = create_update(
			link=link,
			title=title,
			description=description,
			item_url=item_url,
		)

	return Notification.objects.create(
		update=update,
		status=status,
		read_at=read_at,
	)
