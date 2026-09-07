from __future__ import annotations

from pathlib import Path
from typing import Optional

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
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


class SyncedEditor(TextArea):
    def watch_scroll_y(self, old_value: float, new_value: float) -> None:
        super().watch_scroll_y(old_value, new_value)
        if self.app is None:
            return
        try:
            results = self.app.query_one("#results", TextArea)
        except Exception:
            return
        if round(results.scroll_y) != round(new_value):
            results.scroll_to(y=new_value, animate=False, immediate=True)


class AvocadoApp(App):
    CSS = """
    Screen {
        background: #0b0b0f;
        color: #e8e8f0;
    }

    #body {
        height: 100%;
    }

    #editor {
        width: 1fr;
        height: 100%;
        border: none;
        background: #0b0b0f;
    }

    #results {
        width: 44;
        height: 100%;
        border: none;
        border-left: tall #2a2a32;
        background: #0b0b0f;
        color: #cfd0da;
    }

    #status {
        height: 1;
        padding: 0 1;
        color: #8f90a0;
        background: #0b0b0f;
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
        with Vertical():
            with Horizontal(id="body"):
                yield SyncedEditor.code_editor(
                    "",
                    language=None,
                    theme="monokai",
                    soft_wrap=False,
                    show_line_numbers=False,
                    compact=True,
                    highlight_cursor_line=False,
                    id="editor",
                )
                results = TextArea.code_editor(
                    "",
                    language=None,
                    theme="monokai",
                    soft_wrap=False,
                    show_line_numbers=False,
                    read_only=True,
                    show_cursor=False,
                    highlight_cursor_line=False,
                    compact=True,
                    id="results",
                )
                results.can_focus = False
                yield results
            yield Static("", id="status")

    def on_mount(self) -> None:
        editor = self.query_one("#editor", TextArea)
        if self._file_path and self._file_path.exists():
            editor.text = self._file_path.read_text(encoding="utf-8")
        editor.focus()
        self._update_status()
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
        self._update_status()
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
        self._update_status()
        self.action_save()

    def _schedule_evaluate(self) -> None:
        if self._eval_timer is not None:
            self._eval_timer.stop()
        self._eval_timer = self.set_timer(0.15, self._evaluate_now)

    def _evaluate_now(self) -> None:
        editor = self.query_one("#editor", TextArea)
        results = self.query_one("#results", TextArea)

        out = evaluate_source_linewise(editor.text)
        width = max(1, results.size.width - 1)
        cropped = truncate_lines(out.lines, width)
        results.text = "\n".join(cropped)
        if round(results.scroll_y) != round(editor.scroll_y):
            results.scroll_to(y=editor.scroll_y, animate=False, immediate=True)

    def _update_status(self) -> None:
        status = self.query_one("#status", Static)
        if self._file_path is None:
            status.update("avocado  |  Ctrl+O open  Ctrl+S save  Ctrl+Q quit")
            return
        status.update(
            f"avocado {self._file_path}  |  Ctrl+O open  Ctrl+S save  Ctrl+Q quit"
        )
