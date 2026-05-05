from django.core.serializers.json import DjangoJSONEncoder
from django.db import models


class SystemEvent(models.Model):
	class Level(models.TextChoices):
		DEBUG = "debug", "Debug"
		INFO = "info", "Info"
		WARNING = "warning", "Warning"
		ERROR = "error", "Error"
		CRITICAL = "critical", "Critical"

	created_at = models.DateTimeField(auto_now_add=True, db_index=True)
	level = models.CharField(max_length=16, choices=Level.choices, default=Level.INFO, db_index=True)
	source = models.CharField(max_length=120, db_index=True)
	kind = models.CharField(max_length=80, db_index=True)
	message = models.CharField(max_length=1000)
	details = models.JSONField(encoder=DjangoJSONEncoder, default=dict, blank=True)

	class Meta:
		ordering = ["-created_at", "-id"]
		indexes = [
			models.Index(fields=["-created_at", "-id"], name="ops_systeme_created_05a06a_idx"),
			models.Index(fields=["level", "-created_at"], name="ops_systeme_level_58567e_idx"),
			models.Index(fields=["source", "-created_at"], name="ops_systeme_source_29bee4_idx"),
		]

	def __str__(self) -> str:
		return f"{self.created_at:%Y-%m-%d %H:%M:%S} {self.level} {self.source}: {self.message}"


class MaintenanceLock(models.Model):
	key = models.CharField(max_length=80, primary_key=True)
	acquired_at = models.DateTimeField()

	def __str__(self) -> str:
		return f"MaintenanceLock({self.key}, acquired_at={self.acquired_at:%Y-%m-%d %H:%M:%S})"
