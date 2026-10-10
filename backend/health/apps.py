from django.apps import AppConfig
from django.conf import settings
from django.db.models.signals import post_save


class HealthConfig(AppConfig):
	default_auto_field = "django.db.models.BigAutoField"
	name = "health"
	verbose_name = "Health Connect data"

	def ready(self) -> None:
		# Imported here: health.lifecycle imports models, which need the app registry ready.
		from health.lifecycle import delete_rows_of_soft_deleted_user  # noqa: PLC0415

		post_save.connect(
			delete_rows_of_soft_deleted_user, sender=settings.AUTH_USER_MODEL, dispatch_uid="health-soft-deleted-user"
		)
