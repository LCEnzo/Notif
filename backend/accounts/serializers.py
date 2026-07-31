from typing import TYPE_CHECKING, Any

from django.contrib.auth.password_validation import validate_password
from django.db import transaction
from rest_framework import serializers
from rest_framework.serializers import ModelSerializer

from accounts.models import DeviceSession, User

if TYPE_CHECKING:
	_UserModelSerializer = ModelSerializer[User]
	_DeviceSessionModelSerializer = ModelSerializer[DeviceSession]
	_AnySerializer = serializers.Serializer[Any]
else:
	_UserModelSerializer = ModelSerializer
	_DeviceSessionModelSerializer = ModelSerializer
	_AnySerializer = serializers.Serializer


class UserCreationSerializer(_UserModelSerializer):
	class Meta:
		model = User
		fields = ["username", "email", "name", "password"]

	@transaction.atomic
	def create(self, validated_data: dict[str, Any]) -> User:
		password = validated_data.pop("password")

		if "username" not in validated_data:
			validated_data["username"] = validated_data["email"]

		instance = self.Meta.model(**validated_data)
		instance.set_password(password)

		instance.save()
		return instance

	@transaction.atomic
	def update(self, instance: User, validated_data: dict[str, Any]) -> User:
		# Password changes are refused here outright. change_password is the
		# only path: it verifies the current password, which is the one proof a
		# stolen bearer token cannot forge. Accepting a password on a generic
		# PATCH would let any valid access token take the account over. No
		# client has ever used this path - both the deployed and the pending
		# frontend post to change_password.
		if "password" in validated_data:
			raise serializers.ValidationError(
				{"password": "Use the change_password endpoint, which verifies the current password."}
			)

		return super().update(instance, validated_data)

	def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
		# This will only validate password during creation and not during update.
		password = attrs.get("password")
		if self.instance is None and password is None:
			raise serializers.ValidationError({"password": "Password is required."})

		if password is not None:
			validate_password(password)

		return attrs


class UserFullReadSerializer(_UserModelSerializer):
	class Meta:
		model = User
		fields = [
			"name",
			"email",
			"username",
			"is_staff",
			"is_superuser",
			"date_created",
			"date_modified",
			"date_deleted",
		]


class UserMinimalReadSerializer(_UserModelSerializer):
	class Meta:
		model = User
		fields = ["username", "date_created"]


# ── device sessions ──────────────────────────────────────────


class LoginRequestSerializer(_AnySerializer):
	username = serializers.CharField()
	password = serializers.CharField(write_only=True)
	transport = serializers.ChoiceField(
		choices=DeviceSession.Transport.choices,
		help_text=(
			"How this client will present the session. 'cookie' sets an HttpOnly cookie and returns no token; "
			"'bearer' returns the raw token once and sets no cookie. The two are mutually exclusive, and a "
			"token presented through the other transport is rejected."
		),
	)
	device_label = serializers.CharField(max_length=120, required=False, allow_blank=True)


class LoginResponseSerializer(_AnySerializer):
	transport = serializers.ChoiceField(choices=DeviceSession.Transport.choices)
	public_id = serializers.UUIDField(help_text="Handle for this session in the sessions list.")
	token = serializers.CharField(
		allow_null=True,
		help_text=(
			"The raw session token, shown exactly once. Non-null only for transport=bearer; "
			"cookie clients get an HttpOnly cookie instead and never see a token."
		),
	)


class StatusResponseSerializer(_AnySerializer):
	status = serializers.CharField()


class DeviceSessionSerializer(_DeviceSessionModelSerializer):
	"""One live session — in practice, one signed-in device.

	``public_id`` is the handle used to revoke a session; the row's integer
	primary key and its ``token_hash`` are deliberately not exposed.
	"""

	current = serializers.SerializerMethodField(help_text="True for the session that made this request.")

	class Meta:
		model = DeviceSession
		fields = [
			"public_id",
			"device_label",
			"transport",
			"created_at",
			"last_used_at",
			"ip",
			"user_agent",
			"current",
		]
		read_only_fields = fields

	def get_current(self, obj: DeviceSession) -> bool:
		request = self.context.get("request")
		caller = getattr(request, "auth", None)
		return isinstance(caller, DeviceSession) and caller.pk == obj.pk


class SessionRevokeResponseSerializer(_AnySerializer):
	"""Result of revoking one session or all of them."""

	status = serializers.CharField()
	revoked = serializers.IntegerField(help_text="Number of sessions this call revoked.")


# ── password reset ───────────────────────────────────────────


class PasswordResetRequestSerializer(_AnySerializer):
	"""Accepts an email address for password reset."""

	email = serializers.EmailField()

	def validate_email(self, value: str) -> str:
		return value.strip().lower()


class PasswordResetConfirmSerializer(_AnySerializer):
	"""Accepts email, code, and new password to complete reset."""

	email = serializers.EmailField()
	code = serializers.CharField(min_length=6, max_length=6)
	new_password = serializers.CharField(min_length=1)

	def validate_email(self, value: str) -> str:
		return value.strip().lower()

	def validate_code(self, value: str) -> str:
		code = value.strip()
		if not code.isascii() or not code.isdigit():
			raise serializers.ValidationError("Code must contain 6 digits.")
		return code
