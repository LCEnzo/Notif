## Backend Setup

This backend now uses `uv` and the `pyproject.toml` in this directory as the source of truth for dependencies and tooling.

### Local setup

```bash
uv sync --python 3.14
cp .env.example .env
uv run python manage.py migrate
uv run python manage.py runserver
```

By default, the development server listens on `http://localhost:8000`.
For a local-only override, set `BACKEND_PORT` in `backend/.env`.
There is no seeded admin account; create one with `uv run python manage.py createsuperuser`.

### Useful commands

```bash
uv run python manage.py test
uv run pytest
uv run ruff check .
uv run mypy .
```

## How to Login and Register an account

### User Registration:
  - Route: `api/v1/accounts/users/`
  - Method: `POST`
  - Body: 
    ```json
    {
		"username": "new_user",
		"email": "newuser@example.com",
		"password": "securepassword123 securepassword123"
	}
    ```
	> Note: name is an optional field, so is the password. 


### User Login:
  - Route: `api/v1/auth/login/`
  - Method: `POST` (JSON only)
  - Body:
    ```json
    {
        "username": "new_user",
        "password": "securepassword123 securepassword123",
        "transport": "bearer",
        "device_label": "Pixel 8"
    }
    ```
  - `transport: "bearer"` returns the opaque session token once, in the body; send it
    back as `Authorization: Session <token>`. `transport: "cookie"` sets an HttpOnly
    `notif_session` cookie instead and returns no token — browsers only, and unsafe
    methods must then echo the `csrftoken` cookie in `X-CSRFToken`.
  - Sign out with `POST api/v1/auth/login/`'s counterpart, `api/v1/auth/logout/`;
    list and revoke devices under `api/v1/auth/sessions/`.
  
## Docker

Run the backend with Docker Compose from the repository root:

```bash
docker compose --env-file backend/.env up --build backend
```

Notes:

- The backend reads environment variables from `backend/.env`.
- The compose setup stores the SQLite database in a named Docker volume.
- Container startup runs `python manage.py migrate` before starting the Django dev server on the port from `BACKEND_PORT` or `8000`.
- The image installs dependencies from `pyproject.toml` and `uv.lock`, not from `requirements.txt`.
