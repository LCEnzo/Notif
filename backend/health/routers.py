"""Keeps the health app on its own SQLite file and every other app off it.

Code that needs the alias asks ``router.db_for_write(<health model>)`` instead of
naming it, so folding the store back into the default database is a settings
change: drop the ``health`` alias and this router.
"""

from typing import Any

from django.db.models import Model

HEALTH_DB_ALIAS = "health"
_APP_LABEL = "health"


def _is_health(model: type[Model]) -> bool:
	return model._meta.app_label == _APP_LABEL


class HealthRouter:
	def db_for_read(self, model: type[Model], **hints: Any) -> str | None:
		return HEALTH_DB_ALIAS if _is_health(model) else None

	def db_for_write(self, model: type[Model], **hints: Any) -> str | None:
		return HEALTH_DB_ALIAS if _is_health(model) else None

	def allow_relation(self, obj1: Model, obj2: Model, **hints: Any) -> bool | None:
		# A relation across the two files cannot be enforced, so only health-to-health is allowed.
		if _is_health(type(obj1)) or _is_health(type(obj2)):
			return _is_health(type(obj1)) and _is_health(type(obj2))
		return None

	def allow_migrate(self, db: str, app_label: str, model_name: str | None = None, **hints: Any) -> bool | None:
		if app_label == _APP_LABEL:
			return db == HEALTH_DB_ALIAS
		if db == HEALTH_DB_ALIAS:
			return False
		return None
