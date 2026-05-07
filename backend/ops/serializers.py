from rest_framework import serializers

from ops.models import SystemEvent


class SystemEventSerializer(serializers.ModelSerializer[SystemEvent]):
	class Meta:
		model = SystemEvent
		fields = ["id", "created_at", "level", "source", "kind", "message", "details"]
		read_only_fields = fields
