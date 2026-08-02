from django.conf import settings
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase


class StrategyOwnerMigrationTestCase(TransactionTestCase):
	"""The ownership migration splits legacy strategies shared across users."""

	migrate_from = ("monitoring", "0014_strategy_user")
	migrate_to = ("monitoring", "0016_alter_strategy_user")

	def setUp(self) -> None:
		super().setUp()
		if type(getattr(settings, "MIGRATION_MODULES", None)).__name__ == "DisableMigrations":
			self.skipTest("run with --migrations; Backend CI has a dedicated migration-regression step")
		executor = MigrationExecutor(connection)
		other_app_leaves = [node for node in executor.loader.graph.leaf_nodes() if node[0] != "monitoring"]
		from_targets = [self.migrate_from, *other_app_leaves]
		executor.migrate(from_targets)
		old_apps = executor.loader.project_state(from_targets).apps

		User = old_apps.get_model("accounts", "User")
		Strategy = old_apps.get_model("monitoring", "Strategy")
		Link = old_apps.get_model("monitoring", "Link")
		first = User.objects.create(
			username="migration-first",
			email="migration-first@example.com",
			password="!",
		)
		second = User.objects.create(
			username="migration-second",
			email="migration-second@example.com",
			password="!",
		)
		strategy = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["article"]},
		)
		Link.objects.create(name="first", url="https://example.com/first", user=first, strategy=strategy)
		Link.objects.create(name="second", url="https://example.com/second", user=second, strategy=strategy)
		self.first_id = first.pk
		self.second_id = second.pk

		executor = MigrationExecutor(connection)
		to_targets = [self.migrate_to, *other_app_leaves]
		executor.migrate(to_targets)
		self.apps = executor.loader.project_state(to_targets).apps

	def tearDown(self) -> None:
		executor = MigrationExecutor(connection)
		executor.migrate(executor.loader.graph.leaf_nodes())
		super().tearDown()

	def test_shared_strategy_is_cloned_per_owner(self) -> None:
		Link = self.apps.get_model("monitoring", "Link")
		Strategy = self.apps.get_model("monitoring", "Strategy")
		links = list(Link.objects.order_by("user_id"))

		self.assertEqual({link.user_id for link in links}, {self.first_id, self.second_id})
		self.assertEqual(len({link.strategy_id for link in links}), 2)
		for link in links:
			self.assertEqual(Strategy.objects.get(pk=link.strategy_id).user_id, link.user_id)
