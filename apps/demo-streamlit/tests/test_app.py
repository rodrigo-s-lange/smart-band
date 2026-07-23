from __future__ import annotations

import os
from pathlib import Path

from streamlit.testing.v1 import AppTest

from demo_app.views import CLIENT_QUESTION_GROUPS


def test_app_loads_without_exception(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("SMARTBAND_DEMO_ALLOW_NO_AUTH", "true")
    monkeypatch.setenv("SMARTBAND_DEMO_DB", str(tmp_path / "app.sqlite3"))
    app = Path(__file__).resolve().parents[1] / "app.py"
    result = AppTest.from_file(str(app), default_timeout=10).run()
    assert not result.exception
    assert any("Atendimento" in title.value for title in result.title)


def test_client_questions_are_numbered_and_unique() -> None:
    questions = [question for _, group in CLIENT_QUESTION_GROUPS for question in group]
    numbers = [number for number, _, _ in questions]
    assert len(questions) >= 30
    assert len(numbers) == len(set(numbers))
    assert {"1", "4.1", "5", "5.1", "5.2", "9.1"}.issubset(numbers)
