from django.contrib.auth.password_validation import validate_password
from django.db import transaction
from rest_framework import serializers
from rest_framework.serializers import ModelSerializer

from accounts.models import User


class UserCreationSerializer(ModelSerializer):
	class Meta:
		model = User
		fields = ["username", "email", "name", "password"]

	@transaction.atomic
	def create(self, validated_data: dict) -> User:
		password = validated_data.pop("password")

		if "username" not in validated_data:
			validated_data["username"] = validated_data["email"]

		instance = self.Meta.model(**validated_data)
		instance.set_password(password)

		instance.save()
		return instance

	@transaction.atomic
	def update(self, instance: User, validated_data: dict):
		# Ensure a user can only update their own password.
		request = self.context.get("request")
		password = validated_data.pop("password", None)
		if password is not None:
			if request is None or request.user != instance:
				raise serializers.ValidationError({"password": "Only the account owner can change their password."})
			instance.set_password(password)

		return super().update(instance, validated_data)

	def validate(self, attrs):
		# This will only validate password during creation and not during update.
		password = attrs.get("password", None)
		if self.instance is None and password is None:
			raise serializers.ValidationError({"password": "Password is required."})

		if password is not None:
			validate_password(password)

		return attrs


class UserFullReadSerializer(ModelSerializer):
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


class UserMinimalReadSerializer(ModelSerializer):
	class Meta:
		model = User
		fields = ["username", "date_created"]


# ── password reset ───────────────────────────────────────────


class PasswordResetRequestSerializer(serializers.Serializer):
	"""Accepts an email address for password reset."""

	email = serializers.EmailField()

	def validate_email(self, value: str) -> str:
		return value.strip().lower()


class PasswordResetConfirmSerializer(serializers.Serializer):
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
