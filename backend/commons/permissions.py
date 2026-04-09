from typing import Any

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
		has_requester = hasattr(request, 'user') and (not request.user.is_anonymous)
		has_requestee = 'pk' in view.kwargs

		if has_requester and has_requestee:
			requester_pk = int(str(request.user.pk))
			requestee_pk = int(view.kwargs['pk'])

			return requester_pk == requestee_pk

		return False

class IsOwner(permissions.BasePermission):
	"""
	Custom permission to only allow owners of an object to view/edit it.
	"""
	def has_object_permission(self, request: HttpRequest | Request, view: Any, obj: Any) -> bool:
		has_requester = hasattr(request, 'user') and (not request.user.is_anonymous)
		obj_has_owner = hasattr(obj, 'user')
		return has_requester and obj_has_owner and obj.user.pk == request.user.pk


class IsOwnerOrAdmin(permissions.BasePermission):
	"""
	Custom permission to only allow owners of an object or admin to view/edit it.
	"""
	def has_object_permission(self, request: HttpRequest | Request, view: Any, obj: Any) -> bool:
		has_requester = hasattr(request, 'user') and (not request.user.is_anonymous)
		user_is_admin: bool = has_requester and request.user.is_staff or request.user.is_superuser # type: ignore

		obj_has_owner = hasattr(obj, 'user')
		obj_owner_is_requester: bool = has_requester and obj_has_owner and obj.user.pk == request.user.pk

		return obj_owner_is_requester or user_is_admin
