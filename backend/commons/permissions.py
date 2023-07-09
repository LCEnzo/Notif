from rest_framework import permissions
from rest_framework.permissions import BasePermission


class ReadOnly(BasePermission):
    def has_permission(self, request, view) -> bool:
        return request.method in permissions.SAFE_METHODS


class IsRequestingThemselves(BasePermission):
    def has_permission(self, request, view) -> bool:
        has_requester = hasattr(request, 'user') and (not request.user.is_anonymous)
        has_requestee = 'pk' in view.kwargs
        
        if has_requester and has_requestee:
            requester_pk = int(request.user.pk)
            requestee_pk = int(view.kwargs['pk'])
            
            return requester_pk == requestee_pk
        
        return False

