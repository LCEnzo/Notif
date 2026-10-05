import logging

from django.core.exceptions import AppRegistryNotReady
from django.db import OperationalError, ProgrammingError


class SystemEventHandler(logging.Handler):
	"""Best-effort logging handler that mirrors warning/error logs to SystemEvent."""

	def emit(self, record: logging.LogRecord) -> None:
		try:
			# Deferred: dictConfig imports this module inside django.setup(), before the
			# app registry can import models.
			from ops.models import SystemEvent

			SystemEvent.objects.create(
				level=record.levelname.lower(),
				source=record.name[:120],
				kind="log",
				message=self.format(record)[:1000],
				details={
					"pathname": record.pathname,
					"lineno": record.lineno,
					"funcName": record.funcName,
				},
			)
		except AppRegistryNotReady:
			# Emitted while Django is still loading apps; the console handler has the record.
			return
		except OperationalError, ProgrammingError:
			# The table may not exist yet during migrations/startup.
			return
		except Exception:
			self.handleError(record)
