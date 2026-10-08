"""The health app's own SQLite file: routing, table placement, and where the file lives."""

from pathlib import Path

import pytest
from django.conf import settings
from django.db import connections, router
from django.test import TestCase
from pydantic import ValidationError

from accounts.models import User
from health.models import HealthRecord
from health.routers import HEALTH_DB_ALIAS, HealthRouter
from health.tests.support import HEALTH_DATABASES
from notif.config import Settings

_SECRET = "test-secret-key"  # pragma: allowlist secret


def test_health_migrates_only_to_its_own_database_and_nothing_else_does():
	health_router = HealthRouter()

	assert health_router.allow_migrate(HEALTH_DB_ALIAS, "health") is True
	assert health_router.allow_migrate("default", "health") is False
	assert health_router.allow_migrate(HEALTH_DB_ALIAS, "accounts") is False
	assert health_router.allow_migrate(HEALTH_DB_ALIAS, "contenttypes") is False
	assert health_router.allow_migrate("default", "accounts") is None


def test_health_models_read_and_write_through_the_health_alias():
	assert router.db_for_read(HealthRecord) == HEALTH_DB_ALIAS
	assert router.db_for_write(HealthRecord) == HEALTH_DB_ALIAS
	assert router.db_for_write(User) == "default"


def test_relations_never_cross_the_two_files():
	health_router = HealthRouter()
	record = HealthRecord()

	assert health_router.allow_relation(record, HealthRecord()) is True
	assert health_router.allow_relation(record, User()) is False
	assert health_router.allow_relation(User(), User()) is None


def test_the_health_alias_shares_the_default_options_without_sharing_the_dict():
	default, health = settings.DATABASES["default"], settings.DATABASES[HEALTH_DB_ALIAS]

	assert health["OPTIONS"] == default["OPTIONS"]
	assert health["OPTIONS"] is not default["OPTIONS"]
	assert health["NAME"] != default["NAME"]


class TablePlacementTestCase(TestCase):
	databases = HEALTH_DATABASES

	def test_each_file_holds_only_its_own_tables(self):
		health_tables = set(connections[HEALTH_DB_ALIAS].introspection.table_names())
		default_tables = set(connections["default"].introspection.table_names())

		assert {table for table in health_tables if not table.startswith("django_")} == {
			"health_healthaggregate",
			"health_healthdeletion",
			"health_healthingestbatch",
			"health_healthrecord",
			"health_healthsource",
		}
		assert not {table for table in default_tables if table.startswith("health_")}


@pytest.fixture
def _hermetic_env(monkeypatch: pytest.MonkeyPatch) -> None:
	for key in ("SQLITE_PATH", "HEALTH_SQLITE_PATH", "DJANGO_SECRET_KEY"):
		monkeypatch.delenv(key, raising=False)


@pytest.mark.usefixtures("_hermetic_env")
@pytest.mark.parametrize(
	("sqlite_path", "expected"),
	[("db.sqlite3", "health.sqlite3"), ("/app/data/db.sqlite3", str(Path("/app/data/health.sqlite3")))],
)
def test_the_health_file_defaults_to_beside_the_main_one(sqlite_path: str, expected: str):
	config = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET, SQLITE_PATH=sqlite_path)

	assert config.health_sqlite_path == expected


@pytest.mark.usefixtures("_hermetic_env")
def test_an_explicit_health_file_wins():
	config = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET, HEALTH_SQLITE_PATH="elsewhere/health.db")

	assert config.health_sqlite_path == "elsewhere/health.db"


@pytest.mark.usefixtures("_hermetic_env")
def test_one_file_for_both_databases_is_refused():
	with pytest.raises(ValidationError, match="needs its own file"):
		Settings(
			_env_file=None,
			DJANGO_SECRET_KEY=_SECRET,
			SQLITE_PATH="data/db.sqlite3",
			HEALTH_SQLITE_PATH="data/db.sqlite3",
		)
