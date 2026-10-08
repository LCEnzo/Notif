from django.urls import path
from django.urls.resolvers import URLPattern

from health.views import HealthIngestView

urlpatterns: list[URLPattern] = [
	path("ingest/", HealthIngestView.as_view(), name="health-ingest"),
]
