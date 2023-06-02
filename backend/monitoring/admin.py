from django.contrib import admin
from monitoring.models import Link, Strategy

admin.site.register(
	(Link, Strategy)
)
