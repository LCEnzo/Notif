from django.apps import AppConfig
from django.conf import settings
from django.db.models.signals import post_delete, post_save


class HealthConfig(AppConfig):
	default_auto_field = "django.db.models.BigAutoField"
	name = "health"
	verbose_name = "Health Connect data"

	def ready(self) -> None:
		# Import here: health.owners imports models, which needs the app registry ready.
		from health.owners import purge_on_user_hard_delete, purge_on_user_soft_delete  # noqa: PLC0415

		user = settings.AUTH_USER_MODEL
		post_delete.connect(purge_on_user_hard_delete, sender=user, dispatch_uid="health-purge-hard-deleted-user")
		post_save.connect(purge_on_user_soft_delete, sender=user, dispatch_uid="health-purge-soft-deleted-user")
