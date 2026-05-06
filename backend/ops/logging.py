import logging


class SystemEventHandler(logging.Handler):
	"""Best-effort logging handler that mirrors warning/error logs to SystemEvent."""

	def emit(self, record: logging.LogRecord) -> None:
		try:
			from django.db import OperationalError, ProgrammingError

			from ops.models import SystemEvent
		except Exception:
			return

		try:
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
		except OperationalError, ProgrammingError:
			# The table may not exist yet during migrations/startup.
			return
		except Exception:
			self.handleError(record)
