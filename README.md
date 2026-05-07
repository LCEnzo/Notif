# My Update Notifier

This is a personal project for the purpose of practicing programming and to ease my own inconvenience in the form of checking various sites and forums. The aim is to build an app that will gather updates from various websites, blogs and forums, and push notifications to clients.

## Overview

The application consists of two main components:
1. Backend - Built using Django, hosted on a VPS.
2. Frontend - Flutter

## Backend

The backend has the following apps:
1. `accounts` - Manages user account creation, login, and authentication.
2. `url_monitoring` - Handles URL storage, CRUD operations, update checks, and push notifications.

### accounts

- Handles user account creation and login.

### url_monitoring

- Stores URLs with associated metadata
- Manages CRUD operations for URLs
- Checks for updates based on URL categories
- Stores updates for URLs
- Sends push notifications for updates

## Frontend

...

## Getting Started

### Prerequisites

For the backend, use `uv` with Python 3.13.

### Installation and Setup

1. Clone the repository.
	```bash
	git clone https://github.com/your_username/my-update-notifier.git
	cd backend
	```
2. Sync the backend environment.
	```bash
	uv sync --python 3.13
	```
3. Create an `.env` file.
	```bash
	cat .env.example > .env
	```
4. Make and apply Django migrations.
	```bash
	uv run python manage.py makemigrations
	uv run python manage.py migrate
	```
5. Run the Django development server.
	```bash
	uv run python manage.py runserver
	```

6. Create an admin account if you want to use Django admin.
	```bash
	uv run python manage.py createsuperuser
	```

By default, Django listens on `http://localhost:8000`. For a local override, set `BACKEND_PORT` in `backend/.env`.
 
## Misc

### Secret Key Gen

The following will change the Django secret key in `.env`.
```bash
python manage.py regenerate_secret_key
```

## Current status (v0.3.0)

**Backend** — Django REST API with JWT auth, 5 scraping strategies, in-app notifications, OpenAPI docs, rate limiting, and production Docker + compose setup. 73 tests passing.

**Frontend** — Flutter app with login/registration, link/strategy management, notification list, and an About screen.

### Done
- [x] User auth (JWT, registration, dev bootstrap)
- [x] Link CRUD with owner-scoped querysets
- [x] 5 scraping strategies (feed, CSS selectors, forum threadmarks, Kemono, QQ Alerts)
- [x] In-app notifications (unread/read/dismissed, mark-all-read)
- [x] Rate limiting (UserRateThrottle + per-endpoint ScopedRateThrottle)
- [x] OpenAPI schema + Swagger/ReDoc (drf-spectacular)
- [x] Production Dockerfile (gunicorn, HEALTHCHECK, collectstatic)
- [x] CI (ruff, mypy, Django checks, pytest via GitHub Actions)
- [x] Security hardening (HSTS, SSL redirect, secure cookies — gated on production)
- [x] Health/status endpoints (liveness + readiness probes with version/commit info)

### Next up
- [ ] Scheduled scraping (cron on VPS — `manage.py scrape` exists, needs scheduling)
- [ ] Push notifications (Telegram delivery first — token already configured)
- [ ] First deployment (Hetzner VPS + Cloudflare + Porkbun domain)
- [ ] Search endpoint
- [ ] Social login

## Note on tech used:

### Why Python and Django?

I already know Django and Python, and they are good enough for the project. Django is proven in production by a myriad of companies/products including Instagram. The subpar nature of the type system hurts, but for a small projects, it's not a big impediment. FastAPI would be a good alternative, but at the time of starting this project I was unfamiliar with it, and can't be bothered to port this.

### Why SQLite

Ease of use, ease of backup. Good enough for a small project.

### Why Flutter?

I wanted to have one frontend for multiple platforms, and it seems a nice choice. The other option I've considered is using Sveltekit for the web, and potentially a native Android app, but that seems like a needless amount of work for now.

### Why Docker and Hetzner?

Hetzner is cheap. Will look into hosting on AWS/Azure/GCP to learn more about cloud later. Might use DO.

Docker - use for practice, reproducability, and portability.
