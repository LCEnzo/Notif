from typing import TYPE_CHECKING, Any, cast

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, Group, Permission, PermissionsMixin
from django.contrib.auth.validators import UnicodeUsernameValidator
from django.db import models, transaction
from django.db.models.query import QuerySet
from django.utils import timezone

if TYPE_CHECKING:
	_UserManagerBase = BaseUserManager["User"]
else:
	_UserManagerBase = BaseUserManager


class UserManager(_UserManagerBase):
	def create_user(self, email: str, username: str, password: str, **extra_fields: Any) -> User:
		if not email:
			raise ValueError("Email is required")
		email = self.normalize_email(email)
		user = self.model(email=email, username=username, **extra_fields)
		cast(AbstractBaseUser, user).set_password(password)
		user.save(using=self._db)
		return user

	def create_superuser(self, email: str, username: str, password: str, **extra_fields: Any) -> User:
		extra_fields["is_staff"] = True
		extra_fields["is_superuser"] = True
		return self.create_user(email, username, password, **extra_fields)

	def get_queryset(self) -> QuerySet[User]:
		return super().get_queryset().filter(date_deleted__isnull=True)


class User(AbstractBaseUser, PermissionsMixin):
	class Meta:
		verbose_name = "user"
		verbose_name_plural = "users"

	username_validator = UnicodeUsernameValidator()

	name = models.CharField(max_length=64, default="Anon")
	username = models.CharField(
		max_length=150,
		unique=True,
		help_text="Required. 150 characters or fewer. Letters, digits and @/./+/-/_ only.",
		validators=[username_validator],
		error_messages={
			"unique": "A user with that username already exists.",
		},
	)
	email = models.EmailField(unique=True)

	groups = models.ManyToManyField(
		Group,
		blank=True,
		related_name="users",
		related_query_name="users",
	)  # type: ignore[assignment]
	user_permissions = models.ManyToManyField(
		Permission,
		blank=True,
		related_name="users",
		related_query_name="users",
	)  # type: ignore[assignment]

	# Bookkeeping
	date_created = models.DateTimeField(auto_now_add=True)
	date_modified = models.DateTimeField(auto_now=True)
	date_deleted = models.DateTimeField(null=True, blank=True)

	# Django admin panel permission
	is_staff = models.BooleanField(
		"staff status",
		default=False,
		help_text="Designates whether the user can log into this admin site.",
	)
	is_active = models.BooleanField(
		"active",
		default=True,
		help_text=(
			"Designates whether this user should be treated as active. Unselect this instead of deleting accounts."
		),
	)

	objects = UserManager()

	USERNAME_FIELD = "username"
	EMAIL_FIELD = "email"
	REQUIRED_FIELDS = [EMAIL_FIELD]

	# Soft delete by default
	def delete(
		self,
		using: Any | None = None,
		keep_parents: bool = False,
	) -> tuple[int, dict[str, int]]:
		# The row survives, so its sessions would too unless they are revoked
		# here — and then reactivating the account would resurrect credentials
		# that were handed out before the deletion. One transaction, so the
		# account cannot be inactive-with-live-sessions at any observable point.
		from accounts.device_sessions import revoke_all_sessions_for_user
		from accounts.models.device_session import DeviceSession

		with transaction.atomic(using=using):
			self.date_deleted = timezone.now()
			self.is_active = False
			self.save(using=using, update_fields=["date_deleted", "is_active", "date_modified"])
			revoke_all_sessions_for_user(self, reason=DeviceSession.RevokeReason.USER_DEACTIVATED)
		return (1, {self._meta.label: 1})

	def actually_delete(
		self,
		using: Any | None = None,
		keep_parents: bool = False,
	) -> tuple[int, dict[str, int]]:
		return super().delete(using=using, keep_parents=keep_parents)
