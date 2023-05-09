from django.contrib import admin
from models import Link, Strategy

admin.register(
    (Link, Strategy)
)
