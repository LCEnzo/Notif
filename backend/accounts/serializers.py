from typing import TYPE_CHECKING, Any

from django.contrib.auth.password_validation import validate_password
from django.db import transaction
from rest_framework import serializers
from rest_framework.serializers import ModelSerializer

from accounts.models import RefreshSessionFamily, User
from accounts.refresh_sessions import family_id_from_access_token, revoke_all_refresh_families_for_user

if TYPE_CHECKING:
	_UserModelSerializer = ModelSerializer[User]
	_RefreshSessionModelSerializer = ModelSerializer[RefreshSessionFamily]
	_AnySerializer = serializers.Serializer[Any]
else:
	_UserModelSerializer = ModelSerializer
	_RefreshSessionModelSerializer = ModelSerializer
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
		# Ensure a user can only update their own password.
		request = self.context.get("request")
		password = validated_data.pop("password", None)
		if password is not None:
			if request is None or request.user != instance:
				raise serializers.ValidationError({"password": "Only the account owner can change their password."})
			instance.set_password(password)
			# A credential change evicts every other session, same as the
			# change_password action - a PATCH must not be a quieter way to
			# change the password while stolen sessions stay live. The session
			# making the change is kept, identified by its access token's
			# family claim.
			revoke_all_refresh_families_for_user(
				instance,
				reason=RefreshSessionFamily.RevokeReason.PASSWORD_CHANGE,
				except_family=family_id_from_access_token(getattr(request, "auth", None)),
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


# ── token auth ───────────────────────────────────────────────


class TokenLoginRequestSerializer(_AnySerializer):
	username = serializers.CharField()
	password = serializers.CharField(write_only=True)
	remember_me = serializers.BooleanField(default=True, required=False)
	device_label = serializers.CharField(max_length=120, required=False, allow_blank=True)


class TokenAccessResponseSerializer(_AnySerializer):
	access = serializers.CharField()


class TokenRefreshRequestSerializer(_AnySerializer):
	pass


class TokenLogoutResponseSerializer(_AnySerializer):
	status = serializers.CharField()


# ── refresh sessions ─────────────────────────────────────────


class RefreshSessionSerializer(_RefreshSessionModelSerializer):
	"""One active refresh session — in practice, one signed-in device.

	``family_id`` is the public handle used to revoke a session; the row's integer
	primary key is deliberately not exposed.
	"""

	class Meta:
		model = RefreshSessionFamily
		fields = [
			"family_id",
			"created_at",
			"last_used_at",
			"device_label",
			"ip",
			"user_agent",
		]
		read_only_fields = fields


class RefreshSessionRevokeResponseSerializer(_AnySerializer):
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
