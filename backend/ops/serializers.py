from rest_framework import serializers

from ops.models import SystemEvent


class SystemEventSerializer(serializers.ModelSerializer[SystemEvent]):
	class Meta:
		model = SystemEvent
		fields = ["id", "created_at", "level", "source", "kind", "message", "details"]
		read_only_fields = fields


class ClientEventSerializer(serializers.Serializer[dict[str, str]]):
	CATEGORIES = [
		("network_unavailable", "Network unavailable"),
		("timeout", "Timeout"),
		("unauthorized", "Unauthorized"),
		("forbidden", "Forbidden"),
		("validation_failed", "Validation failed"),
		("contract_violation", "Contract violation"),
		("corrupt_local_state", "Corrupt local state"),
		("source_blocked_degraded", "Source blocked or degraded"),
		("server_error", "Server error"),
		("unexpected_failure", "Unexpected failure"),
	]

	category = serializers.ChoiceField(choices=CATEGORIES)
	route = serializers.CharField(max_length=200, required=False, allow_blank=True)
	endpoint = serializers.CharField(max_length=200, required=False, allow_blank=True)
	request_id = serializers.CharField(max_length=120, required=False, allow_blank=True)
	contract_path = serializers.CharField(max_length=200, required=False, allow_blank=True)
	expected = serializers.CharField(max_length=500, required=False, allow_blank=True)
	actual = serializers.CharField(max_length=500, required=False, allow_blank=True)
	app_version = serializers.CharField(max_length=60, required=False, allow_blank=True)
	git_hash = serializers.CharField(max_length=80, required=False, allow_blank=True)
	browser = serializers.CharField(max_length=200, required=False, allow_blank=True)
	message = serializers.CharField(max_length=500, required=False, allow_blank=True)
	stack = serializers.CharField(max_length=2000, required=False, allow_blank=True)


class ClientEventAcceptedSerializer(serializers.Serializer[dict[str, str]]):
	status = serializers.CharField()


class CaddyAccessLogResponseSerializer(serializers.Serializer[dict[str, object]]):
	configured_path = serializers.CharField(required=False)
	results = serializers.ListField(child=serializers.DictField())
