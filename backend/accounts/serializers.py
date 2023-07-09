from django.db import transaction
from rest_framework.serializers import ModelSerializer

from accounts.models import User


class UserCreationSerializer(ModelSerializer):
    class Meta:
        model = User
        fields = ['username', 'email', 'name']

    @transaction.atomic
    def create(self, validated_data: dict) -> User:
        password = validated_data.pop("password", None)
        if 'username' not in validated_data:
            validated_data['username'] = validated_data['email']
        instance = self.Meta.model(**validated_data)

        if password is None:
            instance.set_unusable_password()
        else:
            instance.set_password(password)
    
        instance.save()
        return instance
    
    @transaction.atomic
    def update(self, instance: User, validated_data: dict):
        # Ensure a user can only update their own password.
        request = self.context.get('request')
        if validated_data is not None and (request is None or request.user != instance):
            validated_data.pop('password', None)

        return super().update(instance, validated_data)


class UserFullReadSerializer(ModelSerializer):
    class Meta:
        model = User
        fields = ['name', 'email', 'username', 'date_created', 'date_modified', 'date_deleted']


class UserMinimalReadSerializer(ModelSerializer):
    class Meta:
        model = User
        fields = ['username', 'date_created']

