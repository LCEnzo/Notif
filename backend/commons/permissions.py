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
            requester_pk = int(request.user.pk)
            requestee_pk = int(view.kwargs['pk'])
            
            return requester_pk == requestee_pk
        
        return False

