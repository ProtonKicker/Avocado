from __future__ import annotations

from pathlib import Path
from typing import Optional

from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.screen import ModalScreen
from textual.timer import Timer
from textual.widgets import Input, Static, TextArea

from .evaluator import evaluate_source_linewise, truncate_lines


class OpenFileScreen(ModalScreen[Optional[str]]):
    BINDINGS = [("escape", "cancel", "Cancel")]

    def compose(self) -> ComposeResult:
        yield Input(placeholder="Open file path…", id="path")

    def on_mount(self) -> None:
        self.query_one(Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        value = event.value.strip()
        self.dismiss(value if value else None)

    def action_cancel(self) -> None:
        self.dismiss(None)


class AvocadoApp(App):
    CSS = """
    Screen {
        background: #ffffff;
        color: #111111;
    }

    Horizontal {
        height: 100%;
    }

    #editor {
        width: 1fr;
        height: 100%;
        border: tall #e6e6e6;
    }

    #results {
        width: 48;
        height: 100%;
        border: tall #e6e6e6;
        padding: 0 1;
    }
    """

    BINDINGS = [
        ("ctrl+q", "quit", "Quit"),
        ("ctrl+s", "save", "Save"),
        ("ctrl+o", "open", "Open"),
        ("ctrl+r", "run", "Run"),
    ]

    def __init__(self, file_path: str | None = None) -> None:
        super().__init__()
        self._file_path = Path(file_path).expanduser() if file_path else None
        self._eval_timer: Timer | None = None

    def compose(self) -> ComposeResult:
        with Horizontal():
            yield TextArea(id="editor")
            yield Static("", id="results")

    def on_mount(self) -> None:
        editor = self.query_one("#editor", TextArea)
        if self._file_path and self._file_path.exists():
            editor.text = self._file_path.read_text(encoding="utf-8")
        editor.focus()
        self._evaluate_now()

    def on_text_area_changed(self, event: TextArea.Changed) -> None:
        if event.text_area.id != "editor":
            return
        self._schedule_evaluate()

    def on_resize(self) -> None:
        self._evaluate_now()

    def action_run(self) -> None:
        self._evaluate_now()

    def action_open(self) -> None:
        self.push_screen(OpenFileScreen(), self._open_file_callback)

    def _open_file_callback(self, path: Optional[str]) -> None:
        if not path:
            return

        p = Path(path).expanduser()
        self._file_path = p

        editor = self.query_one("#editor", TextArea)
        if p.exists():
            editor.text = p.read_text(encoding="utf-8")
        else:
            editor.text = ""
        self._evaluate_now()

    def action_save(self) -> None:
        if not self._file_path:
            self.push_screen(OpenFileScreen(), self._save_as_callback)
            return

        editor = self.query_one("#editor", TextArea)
        self._file_path.parent.mkdir(parents=True, exist_ok=True)
        self._file_path.write_text(editor.text, encoding="utf-8")

    def _save_as_callback(self, path: Optional[str]) -> None:
        if not path:
            return
        self._file_path = Path(path).expanduser()
        self.action_save()

    def _schedule_evaluate(self) -> None:
        if self._eval_timer is not None:
            self._eval_timer.stop()
        self._eval_timer = self.set_timer(0.15, self._evaluate_now)

    def _evaluate_now(self) -> None:
        editor = self.query_one("#editor", TextArea)
        results = self.query_one("#results", Static)

        out = evaluate_source_linewise(editor.text)
        width = max(1, results.size.width - 1)
        cropped = truncate_lines(out.lines, width)
        results.update("\n".join(cropped))

