## Backend Setup

This backend now uses `uv` and the `pyproject.toml` in this directory as the source of truth for dependencies and tooling.

### Local setup

```bash
uv sync --python 3.13
cp .env.example .env
uv run python manage.py migrate
uv run python manage.py runserver
```

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
  - Route: `api/v1/token/`
  - Method: `POST`
  - Body: 
    ```json
    {
        "username": "new_user",
        "password": "securepassword123 securepassword123"
    }
    ```
  
## Docker

Run the backend with Docker Compose from the repository root:

```bash
docker compose up --build backend
```

Notes:

- The backend reads environment variables from `backend/.env`.
- The compose setup stores the SQLite database in a named Docker volume.
- Container startup runs `python manage.py migrate` before starting the Django dev server on `0.0.0.0:8000`.
- The image installs dependencies from `pyproject.toml` and `uv.lock`, not from `requirements.txt`.
