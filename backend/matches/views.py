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
from .models import Match as MatchModel

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
        LOGGER.info(
            "MatchListView.get: received request refresh=%s cache_timeout=%s",
            refresh_requested,
            cache_timeout,
        )

        payload = None
        if cache_timeout > 0 and not refresh_requested:
            payload = cache.get(CACHE_KEY)
            LOGGER.debug(
                "MatchListView.get: cache %s",
                "HIT" if payload is not None else "MISS",
            )

        if payload is None:
            try:
                LOGGER.info("MatchListView.get: fetching fresh matches via service")
                matches = fetch_matches()
                LOGGER.info("MatchListView.get: service returned count=%d", len(matches))
                payload = {
                    "count": len(matches),
                    "fetched_at": datetime.now(timezone.utc).isoformat(),
                    "matches": matches,
                }
                if cache_timeout > 0:
                    cache.set(CACHE_KEY, payload, timeout=cache_timeout)
                    LOGGER.debug("MatchListView.get: cached payload under key=%s ttl=%s", CACHE_KEY, cache_timeout)
            except RequestException as exc:
                LOGGER.exception("Failed to fetch ondebola matches: %s", exc)
                payload = None

        # If still no payload (e.g. network failure), read recent snapshot from DB
        if payload is None:
            latest = (
                MatchModel.objects.filter(source="ondebola")
                .order_by("-fetched_at")
                .values("date_text", "time", "home", "away", "competition", "channels", "raw")[:500]
            )
            data = list(latest)
            payload = {
                "count": len(data),
                "fetched_at": datetime.now(timezone.utc).isoformat(),
                "matches": data,
            }

        response = JsonResponse(payload, json_dumps_params={"ensure_ascii": False})
        LOGGER.info("MatchListView.get: responding count=%s", payload.get("count") if isinstance(payload, dict) else None)
        return _apply_cors_headers(response)

    def options(self, request: HttpRequest, *_args, **_kwargs) -> HttpResponse:
        response = HttpResponse(status=204)
        return _apply_cors_headers(response)
