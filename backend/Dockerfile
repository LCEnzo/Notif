FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libxml2-dev libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "uv>=0.11,<1.0"

COPY .python-version pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

RUN useradd --create-home appuser \
    && chown -R appuser:appuser /app

ENV PATH="/app/.venv/bin:${PATH}"

USER appuser

EXPOSE 8000

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
