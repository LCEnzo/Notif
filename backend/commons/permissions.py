from collections.abc import Callable
from typing import Any

from django.db.models.query import QuerySet
from django.http import HttpRequest
from rest_framework import permissions
from rest_framework.permissions import BasePermission
from rest_framework.request import Request


class ReadOnly(BasePermission):
	"""
	Custom permission to only allow access to safe methods.
	"""

	def has_permission(self, request: HttpRequest | Request, view: Any) -> bool:
		return request.method in permissions.SAFE_METHODS


class IsRequestingThemselves(BasePermission):
	"""
	Custom permission to only allow users to access their own data.
	"""

	def has_permission(self, request: HttpRequest | Request, view: Any) -> bool:
		has_requester = hasattr(request, "user") and (not request.user.is_anonymous)
		has_requestee = "pk" in view.kwargs

		if has_requester and has_requestee:
			requester_pk = int(str(request.user.pk))
			requestee_pk = int(view.kwargs["pk"])

			return requester_pk == requestee_pk

		return False


class IsOwner(permissions.BasePermission):
	"""
	Custom permission to only allow owners of an object to view/edit it.
	"""

	def has_object_permission(self, request: HttpRequest | Request, view: Any, obj: Any) -> bool:
		has_requester = hasattr(request, "user") and (not request.user.is_anonymous)
		obj_has_owner = hasattr(obj, "user")
		return has_requester and obj_has_owner and obj.user.pk == request.user.pk


class IsOwnerOrAdmin(permissions.BasePermission):
	"""
	Custom permission to only allow owners of an object or admin to view/edit it.
	"""

	def has_object_permission(self, request: HttpRequest | Request, view: Any, obj: Any) -> bool:
		has_requester = hasattr(request, "user") and (not request.user.is_anonymous)
		user_is_admin: bool = has_requester and (request.user.is_staff or request.user.is_superuser)

		obj_has_owner = hasattr(obj, "user")
		obj_owner_is_requester: bool = has_requester and obj_has_owner and obj.user.pk == request.user.pk

		return obj_owner_is_requester or user_is_admin


class OwnerOrAdminQuerysetMixin:
	"""Mixin that scopes ViewSet querysets to the requesting user.

	Admins see everything, anonymous users see nothing, and everyone else
	sees only objects they own.  Pass *user_filter* for non-standard
	ownership logic (e.g. ``Q(link_set__user=u) | Q(link_set__isnull=True)``
	for StrategyViewSet).
	"""

	def _scoped_queryset(
		self,
		base_queryset: QuerySet[Any],
		*,
		user_filter: Callable[[QuerySet[Any], Any], QuerySet[Any]] | None = None,
	) -> QuerySet[Any]:
		"""Return ``base_queryset`` scoped to the current user.

		When *user_filter* is omitted, the default ownership check is
		``.filter(user=request.user)``.  Pass a callable ``(queryset, user)``
		for custom ownership logic.
		"""
		from accounts.models import User  # avoid circular import

		user = self.request.user  # type: ignore[attr-defined]  # mixin used with DRF ViewSets
		if not isinstance(user, User):
			return base_queryset.none()
		if user.is_staff or user.is_superuser:
			return base_queryset
		if user_filter is not None:
			return user_filter(base_queryset, user)
		return base_queryset.filter(user=user)
