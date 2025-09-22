# QualCanal Backend

This directory contains a minimal Django project that exposes the ondebola.com
match schedule as a JSON API that can be consumed by the Next.js frontend.

## Getting started

```bash
source .venv/bin/activate
pip install -r backend/requirements.txt
python backend/manage.py migrate
python backend/manage.py runserver 0.0.0.0:8000
```

The API is available at `http://localhost:8000/api/matches/`. Append
`?refresh=1` to bypass the cache for a given request.

A lightweight health-check endpoint is available at
`http://localhost:8000/api/health/`.

## Configuration

The project reads the following environment variables at runtime:

| Variable | Description | Default |
| --- | --- | --- |
| `DJANGO_SECRET_KEY` | Secret key used by Django. | `change-me` |
| `DJANGO_DEBUG` | Enable debug mode when set to `true`. | `false` |
| `DJANGO_ALLOWED_HOSTS` | Comma-separated list of allowed hosts. | `localhost,127.0.0.1` |
| `DATABASE_URL` | Optional database connection string. Defaults to SQLite. | `sqlite` |
| `MATCH_CACHE_SECONDS` | Cache TTL for the match response. | `300` |
| `API_ALLOW_ORIGIN` | Value for the `Access-Control-Allow-Origin` header. | `*` |
| `DJANGO_STATIC_ROOT` | Directory to collect static files. | `BASE_DIR/static` |
| `DJANGO_SESSION_COOKIE_SECURE` | Force HTTPS-only cookies when true. | `false` |
| `DJANGO_HSTS_SECONDS` | Enable HTTP Strict Transport Security. | `0` |
| `DJANGO_HSTS_INCLUDE_SUBDOMAINS` | Extend HSTS to sub-domains. | `false` |
| `DJANGO_HSTS_PRELOAD` | Enable HSTS preload directive. | `false` |
| `DJANGO_CSRF_TRUSTED_ORIGINS` | Comma-separated list of trusted origins. | *(empty)* |

## Exporting data manually

Run the management shell or a custom script to call
`matches.services.export_matches_to_files` to generate JSON and CSV snapshots in
a timestamped manner.
