# QualCanal

This repository contains the QualCanal sports broadcasting dashboard and the
supporting Django API that powers it. The project is now fully dockerised so it
can be executed locally or deployed in production with minimal additional
configuration.

## Prerequisites

- Docker 24+
- Docker Compose Plugin 2.24+

## Running with Docker Compose

```bash
docker compose up --build
```

The command builds the production images for both the Next.js frontend and the
Django backend, applies database migrations automatically and starts the stack
with the following defaults:

- Frontend is available on http://localhost:3000
- Backend API is available on http://localhost:8000

The backend health endpoint is exposed at `/api/health/` and is used as the
Compose health-check so the frontend waits until the API is ready before
starting.

## Configuration

The containers read their configuration from environment variables. Update the
values in `docker-compose.yml` or provide them at runtime to suit your
deployment.

### Backend (Django)

| Variable | Description | Default |
| --- | --- | --- |
| `DJANGO_ALLOWED_HOSTS` | Comma-separated hosts served by Django. | `backend,localhost,127.0.0.1` |
| `DJANGO_DEBUG` | Enables Django debug mode when `true`. | `false` |
| `DJANGO_SECRET_KEY` | Secret key used by Django. | `change-me` |
| `MATCH_CACHE_SECONDS` | Cache TTL for match responses. | `300` |
| `DATABASE_URL` | Optional database connection string. | *(empty)* |

### Frontend (Next.js)

| Variable | Description | Default |
| --- | --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | Base URL for the backend API. | `http://backend:8000` |

## Building production images manually

Build the frontend image:

```bash
docker build -t qualcanal-frontend .
```

Build the backend image:

```bash
docker build -t qualcanal-backend ./backend
```

Both images compile the application for production use. The backend image runs
collectstatic during the build and starts Gunicorn behind a security-hardened
configuration that serves pre-compressed static assets via WhiteNoise.
