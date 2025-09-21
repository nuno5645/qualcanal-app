"""URL routes for the matches API."""
from django.urls import path

from .views import HealthcheckView, MatchListView

urlpatterns = [
    path("matches/", MatchListView.as_view(), name="matches"),
    path("health/", HealthcheckView.as_view(), name="health"),
]
