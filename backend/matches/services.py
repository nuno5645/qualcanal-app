"""Service layer containing the ondebola.com scraping logic."""
from __future__ import annotations

import csv
import json
import re
from dataclasses import dataclass, asdict
import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Iterable, Optional

import requests
from bs4 import BeautifulSoup, NavigableString, Tag, FeatureNotFound
from django.utils import timezone
from django.db import transaction

from .models import Match as MatchModel

URL = "https://ondebola.com/"
HEADERS = {
    "User-Agent": "qualcanal-backend/1.0 (+https://example.com)",
}
CHANNEL_REGEX = re.compile(
    r"(dazn\s*\d+|dazn|Canal\s*11|Canal\s*\d+|Sport\.?Tv\d?|Sport\.?TV\d?|Benfica\.?\s*Tv|Benfica\.?\s*TV|C11(?:\s*online)?|TVI)",
    flags=re.IGNORECASE,
)

# Markers that typically introduce competition names or phases
COMPETITION_MARKER = re.compile(
    r"(Liga|Taça|UEFA|Brasileirão|Conferência|Campeões|Qual\.?\s*Mundial|FUTSAL|Feminino|Jorn\.?\s*\d+|J\s*\d+|Euro\s*\d+|Liga\s*PT)",
    flags=re.IGNORECASE,
)

LOGGER = logging.getLogger(__name__)


@dataclass(slots=True)
class Match:
    """Structured representation of a scraped match."""

    date_text: Optional[str]
    time: Optional[str]
    home: Optional[str]
    away: Optional[str]
    competition: Optional[str]
    channels: list[str]
    raw: str

    @property
    def teams(self) -> Optional[str]:
        if self.home and self.away:
            return f"{self.home} - {self.away}"
        return None

    def to_dict(self) -> dict[str, object]:
        """Return a serialisable mapping."""
        data = asdict(self)
        data["teams"] = self.teams
        return data


def text_of(element: Optional[Tag | NavigableString]) -> str:
    """Return stripped text content of a BeautifulSoup element."""
    if element is None:
        return ""
    if isinstance(element, NavigableString):
        return str(element).strip()
    return " ".join(element.stripped_strings)


def parse_line_text(line: str) -> Optional[Match]:
    """Parse a text line into a :class:`Match` instance if possible.

    Heuristics:
    - Split by '|' to isolate segments: [datetime, teams+competition, channels...]
    - Extract time and date from the first segment
    - Extract teams from the second segment, stopping the away name at the first
      competition marker (e.g. 'Liga', 'UEFA', 'Brasileirão') if present
    - Extract channels from the remaining segments using CHANNEL_REGEX
    """
    cleaned = re.sub(r"\s+", " ", line).strip()
    if not cleaned:
        return None
    lowered = cleaned.lower()
    skip_tokens = (
        "agenda de jogos",
        "ver mais jogos",
        "seleccione",
        "fuso horário",
        "instalar site",
    )
    if any(token in lowered for token in skip_tokens):
        return None

    # Split into pipe-separated segments for more reliable parsing
    segments = [seg.strip(" -|") for seg in re.split(r"\s*\|\s*", cleaned) if seg.strip()]

    # Date/time are commonly present in the first segment
    dt_segment = segments[0] if segments else cleaned
    time_match = re.search(r"(\d{1,2}:\d{2})", dt_segment)
    time_str = time_match.group(1) if time_match else None
    date_match = re.search(r"(Seg|Ter|Qua|Qui|Sex|Sab|Dom)?\s*(\d{1,2}\s+[A-Za-z]{3,})", dt_segment)
    date_text = date_match.group(0).strip() if date_match else None

    # Teams usually live in the second segment when present
    teams_segment = segments[1] if len(segments) > 1 else cleaned
    home = away = None
    if "-" in teams_segment:
        left, right = [part.strip() for part in teams_segment.split("-", 1)]
        home = left or None
        comp_match = COMPETITION_MARKER.search(right)
        if comp_match:
            away = right[: comp_match.start()].strip() or None
            comp_from_right = right[comp_match.start():].strip()
        else:
            away = right or None
            comp_from_right = None
    else:
        # Fallback to broad pattern across entire line
        teams_match = re.search(
            r"([A-Za-z0-9ÁÀÂÃÉÈÍÓÔÕÚÇà-ö\s\.]+)\s*-\s*([A-Za-z0-9ÁÀÂÃÉÈÍÓÔÕÚÇà-ö\s\.]+)",
            cleaned,
        )
        if teams_match:
            home = teams_match.group(1).strip()
            right = teams_match.group(2).strip()
            comp_match = COMPETITION_MARKER.search(right)
            away = (right[: comp_match.start()].strip() if comp_match else right) or None
            comp_from_right = right[comp_match.start():].strip() if comp_match else None
        else:
            comp_from_right = None

    # Channels can be present in later segments
    tail_segments = " ".join(segments[2:]) if len(segments) > 2 else (segments[-1] if len(segments) > 0 else "")
    channel_tokens = CHANNEL_REGEX.findall(" ".join([teams_segment, tail_segments]))
    channels = [token.strip() for token in channel_tokens if token and token.strip()]

    # Competition: prefer explicit part found after away within teams segment;
    # otherwise scan remaining segments for a marker
    competition = comp_from_right
    if not competition and len(segments) > 1:
        rest = " ".join(segments[1:])
        comp_scan = COMPETITION_MARKER.search(rest)
        if comp_scan:
            competition = rest[comp_scan.start():].split(" | ")[0].strip()

    if not home and not away and not time_str:
        return None

    return Match(
        date_text=date_text,
        time=time_str,
        home=home,
        away=away,
        competition=competition,
        channels=channels,
        raw=cleaned,
    )


def parse_dom(soup: BeautifulSoup) -> list[Match]:
    """Extract matches using heuristics that follow the ondebola.com layout."""
    header = soup.find(lambda tag: tag.name in {"h2", "h3", "h4"} and "Agenda de jogos" in tag.get_text())
    if not header:
        header = soup.find(
            lambda tag: tag.name in {"h2", "h3", "h4"}
            and "Agenda de jogos em destaque" in tag.get_text()
        )

    matches: list[Match] = []
    if not header:
        LOGGER.debug("parse_dom: header not found; returning 0 matches")
        return matches

    table = header.find_next("table")
    if table:
        parsed_rows = 0
        for row in table.find_all("tr"):
            columns = [text_of(cell) for cell in row.find_all(["td", "th"])]
            if len(columns) < 2:
                continue
            parsed = parse_line_text(" | ".join(columns))
            if parsed:
                matches.append(parsed)
            parsed_rows += 1
        LOGGER.debug("parse_dom: table path parsed_rows=%d matches=%d", parsed_rows, len(matches))
        return matches

    collected_text = []
    current = header.next_sibling
    char_budget = 0
    while current and char_budget < 40000:
        if isinstance(current, Tag):
            text = text_of(current)
            collected_text.append(text)
            char_budget += len(text)
            if "Ver mais jogos" in text:
                break
        elif isinstance(current, NavigableString):
            text = str(current).strip()
            if text:
                collected_text.append(text)
                char_budget += len(text)
        current = current.next_sibling

    for line in (ln.strip() for ln in "\n".join(collected_text).splitlines() if ln.strip()):
        parsed = parse_line_text(line)
        if parsed:
            matches.append(parsed)
    LOGGER.debug("parse_dom: text path budget=%d bytes matches=%d", char_budget, len(matches))
    return matches


def fetch_matches(url: str = URL, headers: Optional[dict[str, str]] = None) -> list[dict[str, object]]:
    """Fetch and return match data from ondebola.com as dictionaries."""
    effective_headers = HEADERS.copy()
    if headers:
        effective_headers.update(headers)

    LOGGER.info("fetch_matches: fetching %s", url)
    http_start = time.perf_counter()
    response = requests.get(url, headers=effective_headers, timeout=15)
    http_ms = int((time.perf_counter() - http_start) * 1000)
    LOGGER.info(
        "fetch_matches: fetched url status=%d elapsed_ms=%d size_bytes=%d",
        response.status_code,
        http_ms,
        len(response.text or ""),
    )
    response.raise_for_status()

    parser_used = "lxml"
    try:
        soup = BeautifulSoup(response.text, "lxml")
    except FeatureNotFound:
        parser_used = "html.parser"
        soup = BeautifulSoup(response.text, "html.parser")
    LOGGER.debug("fetch_matches: parser=%s", parser_used)
    matches = parse_dom(soup)
    LOGGER.debug("fetch_matches: parse_dom returned %d matches", len(matches))

    if not matches:
        LOGGER.warning("fetch_matches: parse_dom returned 0 matches; attempting visible text fallback")
        visible = " ".join(soup.stripped_strings)
        for line in (ln.strip() for ln in visible.splitlines() if ln.strip()):
            parsed = parse_line_text(line)
            if parsed:
                matches.append(parsed)
        LOGGER.debug("fetch_matches: visible text fallback produced %d matches", len(matches))

    unique: dict[str, Match] = {}
    for match in matches:
        key = match.raw[:200]
        if key not in unique:
            unique[key] = match
    LOGGER.info("fetch_matches: returning %d unique matches (raw=%d)", len(unique), len(matches))
    payload = [match.to_dict() for match in unique.values()]

    # Persist a snapshot to the database
    try:
        with transaction.atomic():
            fetched_at = timezone.now()
            for item in payload:
                MatchModel.objects.create(
                    source="ondebola",
                    date_text=str(item.get("date_text") or "") or None,
                    time=str(item.get("time") or "") or None,
                    home=str(item.get("home") or "") or None,
                    away=str(item.get("away") or "") or None,
                    competition=(item.get("competition") or None),
                    channels=list(item.get("channels") or []),
                    raw=str(item.get("raw") or ""),
                    fetched_at=fetched_at,
                )
        LOGGER.info("fetch_matches: persisted %d rows to DB", len(payload))
    except Exception:
        LOGGER.exception("fetch_matches: failed to persist rows to DB")

    print(payload)
    
    
    return payload


def export_matches_to_files(matches: Iterable[dict[str, object]], directory: Path | None = None) -> None:
    """Persist matches to JSON and CSV files. Intended for administrative use."""
    target_dir = Path(directory) if directory else Path.cwd()
    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")

    json_path = target_dir / f"matches_{timestamp}.json"
    csv_path = target_dir / f"matches_{timestamp}.csv"

    match_list = list(matches)

    with json_path.open("w", encoding="utf-8") as json_file:
        json.dump(match_list, json_file, ensure_ascii=False, indent=2)

    with csv_path.open("w", encoding="utf-8", newline="") as csv_file:
        fieldnames = [
            "date_text",
            "time",
            "home",
            "away",
            "teams",
            "competition",
            "channels",
            "raw",
        ]
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        for match in match_list:
            row = dict(match)
            channels = row.get("channels")
            if isinstance(channels, list):
                row["channels"] = ";".join(channels)
            writer.writerow(row)
    LOGGER.info(
        "export_matches_to_files: exported count=%d json=%s csv=%s",
        len(match_list),
        str(json_path),
        str(csv_path),
    )
