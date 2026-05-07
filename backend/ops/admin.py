from django.contrib import admin

from ops.models import SystemEvent


@admin.register(SystemEvent)
class SystemEventAdmin(admin.ModelAdmin[SystemEvent]):
	list_display = ("created_at", "level", "source", "kind", "message")
	list_filter = ("level", "source", "kind")
	search_fields = ("message", "source", "kind")
	readonly_fields = ("created_at",)
