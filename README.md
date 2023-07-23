# My Update Notifier

This is a personal project for the purpose of practicing programming and to ease my own inconvenience in the form of checking various sites and forums. The aim is to build an app that will gather updates from various websites, blogs and forums, and push notifications to clients.

## Overview

The application consists of two main components:
1. Backend - Built using Django, hosted on a VPS.
2. Frontend - Flutter

---

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

---

## Frontend

Tech TBD - Kotlin or Flutter expected

---

## Getting Started

### Prerequisites

As currently, only the backend has code, the prerequisites are:

- Python 3.11 (or higher if no breaking changes)

Instructions assume you are using a Debian derived Linux distro.

### Installation and Setup


1. Clone the repository.
	```bash
	git clone https://github.com/your_username/my-update-notifier.git
	cd backend
	```
2. Create a virtual environment if one does not exist.
	```bash
	python3 -m venv venv
	```
3. Activate the virtual environment.
	```bash
	source venv/bin/activate
	```
4. Install the required Python dependencies.
	```bash
	pip install -r requirements.txt
	```
5. Create an `.env` file.
	```bash
	cat .env.example > .env
	```
6. Apply Django migrations.
	```bash
	python manage.py migrate
	```
7. Run the Django development server.
	```bash
	python manage.py runserver
	```

## Misc

### Secret Key Gen

The following will change the Django secret key in `.env`.
```bash
python manage.py regenerate_secret_key
```


## TODOs
* Create Django app
  * Create accounts app - Initial implementation done
  * Create URL monitoring app - Initial implementation done
  * Fix timezone code - Given default zones, unsure if that's fine
  * Set up environ - Done
* Create some kind of client
  * Add registration
  * Add basic account management (CRUD)
  * Add UI for URL/link (CRUD)
  * Add push notification receiver
* Create full end to end tests if not difficult
* Create docker image for server
* Figure out deployment

Should polish as the project is being written. This includes:
* OpenAPI documentation (would be great if something like FastAPI docs could be had)
* API versioning - kinda? JWT stuff is under `/api/`, while the rest is under `/api/v1/`
* Rate limiting
* CI/CD for making migrations, deployment, and running tests, among other things
* Social login/register
* End to end testing
* Refactor arch for scalability (examples include adding , , ) 
  * caching (redis?)
  * refactoring scraping 
	* to limit per second requests to a single domain	
	* spreading out requests over time
	* serve multiple users (who have the same link) with a single request
	* ...
* Add Selenium as a (fallback) option
* Investigate stuff such as scrapy
* Discord and/or Slack bots
* Email notifications

---

## Note on tech used:

### Why Python and Django?

I already know Django and Python, and they are good enough for the project. Django is proven in production by a myriad of companies/products including Instagram. The subpar nature of the type system hurts, but for a small projects, it's not an impediment.

### Why Postgresql?

I wanted to try it out, and learn a little about DBs. In practice, a better choice would've been SQLite for the simplicity. Postgresql is overkill.

### Why Flutter?

I wanted to have one frontend for multiple platforms, and it seems a nice choice. The other option I've considered is using Sveltekit for the web, and potentially a native Android app, but that seems like a needless amount of work for now.

### Why Docker and Hetzner?

Hetzner is cheap. Will look into hosting on AWS/Azure/GCP to learn more about cloud later.

Docker - practice and portability.
