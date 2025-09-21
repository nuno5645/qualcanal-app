"""Service layer containing the ondebola.com scraping logic."""
from __future__ import annotations

import csv
import json
import re
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Iterable, Optional

import requests
from bs4 import BeautifulSoup, NavigableString, Tag, FeatureNotFound

URL = "https://ondebola.com/"
HEADERS = {
    "User-Agent": "qualcanal-backend/1.0 (+https://example.com)",
}
CHANNEL_REGEX = re.compile(
    r"(dazn\s*\d+|Canal\s*\d+|Sport[Tt]\.Tv\d|Sport\.Tv\d|Benfica\.Tv|C11|Sport\.Tv)",
    flags=re.IGNORECASE,
)


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
    """Parse a text line into a :class:`Match` instance if possible."""
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

    time_match = re.search(r"(\d{1,2}:\d{2})", cleaned)
    time_str = time_match.group(1) if time_match else None

    teams_match = re.search(
        r"([A-Za-z0-9ÁÀÂÃÉÈÍÓÔÕÚÇà-ö\s\.]+)\s*-\s*([A-Za-z0-9ÁÀÂÃÉÈÍÓÔÕÚÇà-ö\s\.]+)",
        cleaned,
    )
    home = away = None
    if teams_match:
        home = teams_match.group(1).strip()
        away = teams_match.group(2).strip()

    date_match = re.search(r"(Seg|Ter|Qua|Qui|Sex|Sab|Dom)?\s*(\d{1,2}\s+[A-Za-z]{3,})", cleaned)
    date_text = date_match.group(0).strip() if date_match else None

    competition = None
    channels: list[str] = []
    if teams_match:
        trailing = cleaned[teams_match.end():].strip()
        parts = [part.strip() for part in re.split(r"\s{2,}|\|", trailing) if part.strip()]
        if parts:
            competition = parts[0]
            if len(parts) > 1:
                channels = parts[1:]
            else:
                channel_tokens = CHANNEL_REGEX.findall(trailing)
                channels = channel_tokens
                if channel_tokens:
                    competition = CHANNEL_REGEX.sub("", competition or trailing).strip(" -|") or None
    else:
        maybe_competition = re.search(
            r"(Liga|Taça|UEFA|Brasileirão|Qual\. Mundial|FUTSAL|Feminino)",
            cleaned,
            flags=re.IGNORECASE,
        )
        competition = maybe_competition.group(0) if maybe_competition else None
        channels = CHANNEL_REGEX.findall(cleaned)

    channels = [channel.strip() for channel in channels if channel and channel.strip()]

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
        return matches

    table = header.find_next("table")
    if table:
        for row in table.find_all("tr"):
            columns = [text_of(cell) for cell in row.find_all(["td", "th"])]
            if len(columns) < 2:
                continue
            parsed = parse_line_text(" | ".join(columns))
            if parsed:
                matches.append(parsed)
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

    return matches


def fetch_matches(url: str = URL, headers: Optional[dict[str, str]] = None) -> list[dict[str, object]]:
    """Fetch and return match data from ondebola.com as dictionaries."""
    effective_headers = HEADERS.copy()
    if headers:
        effective_headers.update(headers)

    response = requests.get(url, headers=effective_headers, timeout=15)
    response.raise_for_status()

    try:
        soup = BeautifulSoup(response.text, "lxml")
    except FeatureNotFound:
        soup = BeautifulSoup(response.text, "html.parser")
    matches = parse_dom(soup)

    if not matches:
        visible = " ".join(soup.stripped_strings)
        for line in (ln.strip() for ln in visible.splitlines() if ln.strip()):
            parsed = parse_line_text(line)
            if parsed:
                matches.append(parsed)

    unique: dict[str, Match] = {}
    for match in matches:
        key = match.raw[:200]
        if key not in unique:
            unique[key] = match

    return [match.to_dict() for match in unique.values()]


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
