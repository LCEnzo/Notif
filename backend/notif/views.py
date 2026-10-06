"""Project-wide error views, wired in notif/urls.py."""

from django.http import HttpRequest, HttpResponse, JsonResponse
from django.views import defaults

_API_PREFIX = "/api/"


def page_not_found(request: HttpRequest, exception: Exception) -> HttpResponse:
	"""A JSON ``{"detail"}`` 404 under /api/, Django's own page elsewhere.

	For paths no URL pattern matches, which never reach DRF, e.g. ``/links/1.5/``.
	"""
	if request.path_info.startswith(_API_PREFIX):
		return JsonResponse({"detail": "Not found."}, status=404)
	return defaults.page_not_found(request, exception)
