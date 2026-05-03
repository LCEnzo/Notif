from django.contrib import admin

from monitoring.models import Link, Notification, Strategy, Update

admin.site.register((Link, Strategy, Update, Notification))
