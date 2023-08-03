
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.serializers import BaseSerializer
from rest_framework.viewsets import ModelViewSet

from accounts.models import User
from accounts.serializers import (
	UserCreationSerializer,
	UserFullReadSerializer,
	UserMinimalReadSerializer,
)
from commons.permissions import IsRequestingThemselves, ReadOnly


class UserViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated, (ReadOnly | IsRequestingThemselves | IsAdminUser)]
	queryset = User.objects.all()
	
	def get_serializer_class(self) -> type[BaseSerializer]:
		requester_pk = self.request.user.pk if not self.request.user.is_anonymous else None
		wanted_pk = self.kwargs.get('pk', None)

		match (self.request.method, requester_pk):
			case ("POST" | "PUT" | "PATCH", _):
				return UserCreationSerializer
			case ("GET", wanted_pk) if wanted_pk is not None: 
				return UserFullReadSerializer
			case _:
				return UserMinimalReadSerializer

	def get_permissions(self):
		# Account creation, ie. registration, needs to work for visitors without an account
		if self.request.method == "POST": 
			return []

		return super().get_permissions()

	@action(detail=False, methods=['get', 'post'], permission_classes=[IsAuthenticated])
	def get_my_info(self, request: Request) -> Response:
		user = request.user
		assert type(user) == User
		return Response(
			status=status.HTTP_200_OK, 
			data=self.get_serializer_class()(user).data
		)
