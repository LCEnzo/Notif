from django.db import models
from django.contrib.auth.models import BaseUserManager, AbstractBaseUser, PermissionsMixin, Group, Permission


class UserManager(BaseUserManager):
	def create_user(self, email: str, username: str, password: str, **extra_fields):
		if not email:
			raise ValueError("Email is required")
		email = self.normalize_email(email)
		user = self.model(email=email, username=username, **extra_fields)
		user.set_password(password)
		user.save(using=self._db)
		return user

	def create_superuser(self, email: str, username: str, password: str, **extra_fields):
		extra_fields.setdefault("is_staff", True)
		extra_fields.setdefault("is_superuser", True)
		return self.create_user(email, username, password, **extra_fields)        


class User(AbstractBaseUser, PermissionsMixin):
	username = models.CharField(max_length=50)
	email = models.EmailField(unique=True)
	groups = models.ManyToManyField(
		Group, 
		blank=True,
		related_name='users', 
		related_query_name='users',
	)
	user_permissions = models.ManyToManyField(
		Permission,
		blank=True,
		related_name='users', 
		related_query_name='users',
	)

	objects = UserManager()

	USERNAME_FIELD = 'username'
	EMAIL_FIELD = 'email'
