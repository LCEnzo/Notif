"""How settings_base turns the EMAIL_* environment into Django's MAILERS.

The variable names are the deployment contract, so each case starts from them.
Django's own mailer construction checks the result: it rejects OPTIONS a backend
does not take, which comparing dicts alone would miss.
"""

import runpy
import sys
import types
from pathlib import Path
from typing import Any

import pytest
from django.core import mail
from django.core.mail.backends.base import BaseEmailBackend
from django.core.mail.backends.console import EmailBackend as ConsoleBackend
from django.core.mail.backends.locmem import EmailBackend as LocmemBackend
from django.core.mail.backends.smtp import EmailBackend as SmtpBackend
from django.test import override_settings

from notif import config

_SMTP = "django.core.mail.backends.smtp.EmailBackend"
_CONSOLE = "django.core.mail.backends.console.EmailBackend"
_LOCMEM = "django.core.mail.backends.locmem.EmailBackend"

# Cleared before each case so the shell or CI environment cannot leak in.
_AMBIENT_KEYS = (
	"EMAIL_BACKEND",
	"EMAIL_HOST",
	"EMAIL_PORT",
	"EMAIL_HOST_USER",
	"EMAIL_HOST_PASSWORD",
	"EMAIL_USE_TLS",
	"EMAIL_TIMEOUT",
	"RESEND_API_KEY",
	"NOTIF_ENV",
	"DEBUG",
	"DEV_BOOTSTRAP_LOGIN_ENABLED",
)
_SECRET = "test-secret-key"  # pragma: allowlist secret
_CREDENTIAL = "smtp-credential"  # pragma: allowlist secret

# Every value differs from config's default, so an ignored variable shows.
_CUSTOM_SMTP_ENV = {
	"EMAIL_HOST": "smtp.mail.test",
	"EMAIL_PORT": "2525",
	"EMAIL_HOST_USER": "mailer",
	"EMAIL_USE_TLS": "false",
	"EMAIL_TIMEOUT": "7",
}


def _execute(settings_module: str) -> dict[str, Any]:
	# run_path, not run_module: settings_test.py matches pytest's *_test.py
	# pattern, so the assertion-rewriting import hook claims it.
	return runpy.run_path(str(Path(config.__file__).with_name(f"{settings_module}.py")))


def _configure(monkeypatch: pytest.MonkeyPatch, **env: str) -> None:
	"""Point ``notif.config.settings`` at a Settings built from exactly ``env``."""
	for key in _AMBIENT_KEYS:
		monkeypatch.delenv(key, raising=False)
	for key, value in env.items():
		monkeypatch.setenv(key, value)
	monkeypatch.setattr(config, "settings", config.Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET))


def _base_mailers(monkeypatch: pytest.MonkeyPatch, **env: str) -> dict[str, Any]:
	"""MAILERS as settings_base derives it from exactly ``env``."""
	_configure(monkeypatch, **env)
	mailers: dict[str, Any] = _execute("settings_base")["MAILERS"]
	return mailers


def _default_mailer(mailers: dict[str, Any]) -> BaseEmailBackend:
	"""The backend Django builds for ``mailers["default"]``. Construction opens no connection."""
	with override_settings(MAILERS=mailers):
		return mail.mailers.default


def _smtp_parameters(backend: BaseEmailBackend) -> tuple[object, ...]:
	assert isinstance(backend, SmtpBackend)
	return (
		backend.host,
		backend.port,
		backend.username,
		backend.password,
		backend.use_tls,
		backend.use_ssl,
		backend.timeout,
	)


def test_resend_api_key_alone_reaches_resend_smtp(monkeypatch: pytest.MonkeyPatch) -> None:
	backend = _default_mailer(_base_mailers(monkeypatch, RESEND_API_KEY=_CREDENTIAL))

	assert _smtp_parameters(backend) == ("smtp.resend.com", 587, "resend", _CREDENTIAL, True, False, 10)


def test_every_smtp_variable_reaches_its_option(monkeypatch: pytest.MonkeyPatch) -> None:
	mailers = _base_mailers(monkeypatch, EMAIL_HOST_PASSWORD=_CREDENTIAL, **_CUSTOM_SMTP_ENV)

	assert _smtp_parameters(_default_mailer(mailers)) == (
		"smtp.mail.test",
		2525,
		"mailer",
		_CREDENTIAL,
		False,
		False,
		7,
	)


@pytest.mark.parametrize(
	"credential_env",
	[{}, {"EMAIL_HOST_PASSWORD": ""}, {"RESEND_API_KEY": ""}],
	ids=["unset", "empty-password", "empty-api-key"],
)
def test_no_credential_selects_the_console(credential_env: dict[str, str], monkeypatch: pytest.MonkeyPatch) -> None:
	# The console must win and get no OPTIONS, which it would reject.
	mailers = _base_mailers(monkeypatch, **_CUSTOM_SMTP_ENV, **credential_env)

	assert mailers == {"default": {"BACKEND": _CONSOLE}}
	assert type(_default_mailer(mailers)) is ConsoleBackend


@pytest.mark.parametrize(
	("env", "backend_class"),
	[
		({"EMAIL_BACKEND": _CONSOLE, "EMAIL_HOST_PASSWORD": _CREDENTIAL}, ConsoleBackend),
		({"EMAIL_BACKEND": _LOCMEM, "RESEND_API_KEY": _CREDENTIAL}, LocmemBackend),
	],
	ids=["console-despite-password", "locmem-despite-api-key"],
)
def test_explicit_backend_beats_credential_selection(
	env: dict[str, str], backend_class: type[BaseEmailBackend], monkeypatch: pytest.MonkeyPatch
) -> None:
	backend = _default_mailer(_base_mailers(monkeypatch, **env))

	assert type(backend) is backend_class


def test_explicit_smtp_beats_a_missing_credential(monkeypatch: pytest.MonkeyPatch) -> None:
	backend = _default_mailer(_base_mailers(monkeypatch, EMAIL_BACKEND=_SMTP, **_CUSTOM_SMTP_ENV))

	assert _smtp_parameters(backend) == ("smtp.mail.test", 2525, "mailer", None, False, False, 7)


def test_test_settings_capture_mail_whatever_base_selected(monkeypatch: pytest.MonkeyPatch) -> None:
	_configure(monkeypatch, EMAIL_HOST_PASSWORD=_CREDENTIAL)
	smtp_base = _execute("settings_base")
	assert smtp_base["MAILERS"]["default"]["BACKEND"] == _SMTP
	# settings_test star-imports the cached settings_base, so swap this one in.
	module = types.ModuleType("notif.settings_base")
	vars(module).update((name, value) for name, value in smtp_base.items() if not name.startswith("__"))
	monkeypatch.setitem(sys.modules, "notif.settings_base", module)

	mailers = _execute("settings_test")["MAILERS"]

	assert mailers == {"default": {"BACKEND": _LOCMEM}}
	assert type(_default_mailer(mailers)) is LocmemBackend
