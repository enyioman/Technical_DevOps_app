# syntax=docker/dockerfile:1

# ---- builder ----
FROM python:3.11-slim AS builder
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /w

COPY requirements.txt .
RUN python -m pip install --upgrade pip wheel \
 && python -m pip install --prefix=/install -r requirements.txt \
 && python -m pip install --prefix=/install gunicorn

# ---- runtime ----
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Create user early (no big layer)
RUN useradd -r -u 10001 app
WORKDIR /app

# Python deps
COPY --from=builder /install /usr/local

# App code (ownership set here, no chown -R)
# If your repo is big, prefer copying only what you need, e.g.:
# COPY --chown=app:app mysite/ manage.py pyproject.toml ./
COPY --chown=app:app . /app

USER app
EXPOSE 8000
CMD ["gunicorn", "mysite.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60"]
