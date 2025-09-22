"""Database models for the matches app."""
from __future__ import annotations

from django.db import models
from django.utils import timezone


class Match(models.Model):
    """Persisted representation of one scraped match row."""

    source = models.CharField(max_length=32, default="ondebola", db_index=True)

    date_text = models.CharField(max_length=64, null=True, blank=True)
    time = models.CharField(max_length=16, null=True, blank=True)
    home = models.CharField(max_length=128, null=True, blank=True)
    away = models.CharField(max_length=128, null=True, blank=True)
    competition = models.CharField(max_length=128, null=True, blank=True)
    channels = models.JSONField(default=list)
    raw = models.TextField()

    fetched_at = models.DateTimeField(default=timezone.now, db_index=True)

    class Meta:
        indexes = [
            models.Index(fields=["source", "fetched_at"]),
        ]

    @property
    def teams(self) -> str | None:
        if self.home and self.away:
            return f"{self.home} - {self.away}"
        return None

    def to_dict(self) -> dict[str, object]:
        return {
            "date_text": self.date_text or "",
            "time": self.time or "",
            "home": self.home or "",
            "away": self.away or "",
            "teams": self.teams or (f"{self.home or ''} - {self.away or ''}".strip()),
            "competition": self.competition,
            "channels": list(self.channels or []),
            "raw": self.raw,
        }


