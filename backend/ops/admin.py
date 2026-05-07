from typing import TYPE_CHECKING

from django.contrib import admin

from ops.models import SystemEvent

if TYPE_CHECKING:
	_SystemEventModelAdmin = admin.ModelAdmin[SystemEvent]
else:
	_SystemEventModelAdmin = admin.ModelAdmin


@admin.register(SystemEvent)
class SystemEventAdmin(_SystemEventModelAdmin):
	list_display = ("created_at", "level", "source", "kind", "message")
	list_filter = ("level", "source", "kind")
	search_fields = ("message", "source", "kind")
	readonly_fields = ("created_at",)
