"""Project-wide error views, wired in notif/urls.py."""

from django.http import HttpRequest, HttpResponse, JsonResponse
from django.views import defaults

_API_PREFIX = "/api/"


def page_not_found(request: HttpRequest, exception: Exception) -> HttpResponse:
	"""A JSON 404 under /api/, and Django's own page everywhere else.

	DRF renders the 404s its views raise, but a path the URLconf cannot match
	never reaches DRF: ``/links/1.5/`` is one, since the router's lookup pattern
	refuses a dot. Under /api/ that 404 has the ``{"detail": ...}`` body every
	documented API 404 has, instead of an HTML page no API client can read.
	"""
	if request.path_info.startswith(_API_PREFIX):
		return JsonResponse({"detail": "Not found."}, status=404)
	return defaults.page_not_found(request, exception)
