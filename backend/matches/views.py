"""HTTP views for the matches API."""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from django.conf import settings
from django.core.cache import cache
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.views import View

from requests import RequestException

from .services import fetch_matches

LOGGER = logging.getLogger(__name__)
CACHE_KEY = "matches:ondebola"


def _apply_cors_headers(response: HttpResponse) -> HttpResponse:
    allow_origin = getattr(settings, "API_ALLOW_ORIGIN", "*") or "*"
    response["Access-Control-Allow-Origin"] = allow_origin
    response["Access-Control-Allow-Methods"] = "GET, OPTIONS"
    response["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    return response


class HealthcheckView(View):
    """Return a simple success payload for uptime checks."""

    http_method_names = ["get", "options"]

    def get(self, request: HttpRequest, *_args, **_kwargs) -> JsonResponse:
        payload = {"status": "ok"}
        response = JsonResponse(payload)
        return _apply_cors_headers(response)

    def options(self, request: HttpRequest, *_args, **_kwargs) -> HttpResponse:
        response = HttpResponse(status=204)
        return _apply_cors_headers(response)


class MatchListView(View):
    """Expose the ondebola.com schedule as a cached JSON API."""

    http_method_names = ["get", "options"]

    def get(self, request: HttpRequest, *_args, **_kwargs) -> JsonResponse:
        refresh_requested = request.GET.get("refresh") in {"1", "true", "yes"}
        cache_timeout = max(int(getattr(settings, "MATCH_CACHE_SECONDS", 0)), 0)

        payload = None
        if cache_timeout > 0 and not refresh_requested:
            payload = cache.get(CACHE_KEY)

        if payload is None:
            try:
                matches = fetch_matches()
            except RequestException as exc:
                LOGGER.exception("Failed to fetch ondebola matches: %s", exc)
                response = JsonResponse({"error": "Failed to fetch matches"}, status=503)
                return _apply_cors_headers(response)

            payload = {
                "count": len(matches),
                "fetched_at": datetime.now(timezone.utc).isoformat(),
                "matches": matches,
            }
            if cache_timeout > 0:
                cache.set(CACHE_KEY, payload, timeout=cache_timeout)

        response = JsonResponse(payload, json_dumps_params={"ensure_ascii": False})
        return _apply_cors_headers(response)

    def options(self, request: HttpRequest, *_args, **_kwargs) -> HttpResponse:
        response = HttpResponse(status=204)
        return _apply_cors_headers(response)
