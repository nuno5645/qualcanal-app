"""Tests for the matches service layer."""
from __future__ import annotations

from unittest.mock import Mock, patch

from bs4 import BeautifulSoup
from django.test import SimpleTestCase

from matches import services


class ParseLineTextTests(SimpleTestCase):
    """Validate the text parsing heuristics."""

    def test_parses_basic_line(self) -> None:
        line = "Dom 21 Set 14:00 Benfica - Porto Liga Portugal Sport.Tv1"
        match = services.parse_line_text(line)
        self.assertIsNotNone(match)
        assert match is not None
        self.assertEqual(match.time, "14:00")
        self.assertEqual(match.home, "Benfica")
        self.assertEqual(match.away, "Porto")
        self.assertEqual(match.competition, "Liga Portugal")
        self.assertIn("Sport.Tv1", match.channels)

    def test_returns_none_for_non_match_text(self) -> None:
        line = "Agenda de jogos"
        self.assertIsNone(services.parse_line_text(line))


class FetchMatchesTests(SimpleTestCase):
    """Ensure the HTTP integration layer behaves as expected."""

    SAMPLE_HTML = """
    <html>
        <body>
            <h2>Agenda de jogos</h2>
            <table>
                <tr>
                    <th>Data</th>
                    <th>Jogo</th>
                </tr>
                <tr>
                    <td>Dom 21 Set</td>
                    <td>14:00 Benfica - Porto Liga Portugal Sport.Tv1</td>
                </tr>
            </table>
        </body>
    </html>
    """

    @patch("matches.services.requests.get")
    def test_fetch_matches_returns_unique_entries(self, mock_get: Mock) -> None:
        response = Mock()
        response.text = self.SAMPLE_HTML
        response.raise_for_status.return_value = None
        mock_get.return_value = response

        matches = services.fetch_matches()
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0]["home"], "Benfica")
        self.assertEqual(matches[0]["away"], "Porto")

    def test_parse_dom_handles_table_structure(self) -> None:
        soup = BeautifulSoup(self.SAMPLE_HTML, "html.parser")
        matches = services.parse_dom(soup)
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].home, "Benfica")
