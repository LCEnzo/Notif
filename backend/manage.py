#!/usr/bin/env python
"""Django's command-line utility for administrative tasks."""
import os
import sys

try:
	from dotenv import load_dotenv
except ImportError:
	load_dotenv = None


def main():
	"""Run administrative tasks."""
	if load_dotenv is not None:
		load_dotenv()

	if len(sys.argv) == 2 and sys.argv[1] == 'runserver':
		backend_port = os.getenv('BACKEND_PORT')
		if backend_port:
			runserver_host = os.getenv('RUNSERVER_HOST', '127.0.0.1')
			sys.argv.append(f'{runserver_host}:{backend_port}')

	os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'notif.settings')
	try:
		from django.core.management import execute_from_command_line
	except ImportError as exc:
		raise ImportError(
			"Couldn't import Django. Are you sure it's installed and "
			"available on your PYTHONPATH environment variable? Did you "
			"forget to activate a virtual environment?"
		) from exc
	execute_from_command_line(sys.argv)


if __name__ == '__main__':
	main()
