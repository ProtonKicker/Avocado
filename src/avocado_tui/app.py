from __future__ import annotations

from pathlib import Path
from typing import Optional

from rich.table import Table
from rich.text import Text
from textual import events
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.timer import Timer
from textual.widgets import Input, Static, TextArea

from .config import (
    MAX_RESULTS_WIDTH,
    MIN_RESULTS_WIDTH,
    load_results_width,
    save_results_width,
)
from .evaluator import evaluate_source_linewise, truncate_lines
from .prelude import build_prelude_source, prelude_line_count


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


class Divider(Static):
    def on_mouse_down(self, event: events.MouseDown) -> None:
        app = self.app
        if not isinstance(app, AvocadoApp):
            return
        app._dragging = True
        self.set_class(True, "-dragging")
        self.capture_mouse()

    def on_mouse_up(self, event: events.MouseUp) -> None:
        app = self.app
        if not isinstance(app, AvocadoApp):
            return
        if not app._dragging:
            return
        app._dragging = False
        self.set_class(False, "-dragging")
        self.release_mouse()
        save_results_width(app._file_path, app._results_width)

    def on_mouse_move(self, event: events.MouseMove) -> None:
        app = self.app
        if not isinstance(app, AvocadoApp):
            return
        if not app._dragging:
            return

        results = app.query_one("#results", TextArea)
        screen_w = app.size.width
        new_width = screen_w - event.screen_x - 1
        app._results_width = max(MIN_RESULTS_WIDTH, min(MAX_RESULTS_WIDTH, new_width))
        results.styles.width = app._results_width
        app.refresh(layout=True)
        app._evaluate_now()


class AvocadoApp(App):
    CSS = """
    Screen {
        background: #0b0b0f;
        color: #e8e8f0;
    }

    #banner {
        height: 1;
        padding: 0 1;
        color: #cfd0da;
        background: #0b0b0f;
    }

    #body {
        height: 1fr;
    }

    #editor {
        width: 1fr;
        height: 100%;
        border: none;
        background: #0b0b0f;
    }

    #divider {
        width: 1;
        height: 100%;
        background: #1a1a22;
        color: #4a4a55;
    }

    #divider:hover {
        background: #2a2a35;
        color: #8a8a95;
    }

    #divider.-dragging {
        background: #3a3a48;
        color: #cfd0da;
    }

    #results {
        width: 44;
        height: 100%;
        border: none;
        background: #0b0b0f;
        color: #cfd0da;
    }

    """

    BINDINGS = [
        ("ctrl+q", "quit", "Quit"),
        ("ctrl+s", "save", "Save"),
        ("ctrl+o", "open", "Open"),
        ("ctrl+r", "run", "Run"),
        ("ctrl+right", "widen_results", "Widen results"),
        ("ctrl+left", "narrow_results", "Narrow results"),
        ("ctrl+backslash", "toggle_results", "Toggle results"),
    ]

    RESIZE_STEP = 4

    def __init__(self, file_path: str | None = None) -> None:
        super().__init__()
        self._file_path = (
            Path(file_path).expanduser().resolve(strict=False) if file_path else None
        )
        self._eval_timer: Timer | None = None
        self._results_width: int = load_results_width(self._file_path)
        self._dragging = False
        self._results_visible = True

    def compose(self) -> ComposeResult:
        with Vertical():
            yield Static("", id="banner")
            with Horizontal(id="body"):
                yield SyncedEditor.code_editor(
                    "",
                    language=None,
                    theme="css",
                    soft_wrap=False,
                    show_line_numbers=False,
                    compact=True,
                    highlight_cursor_line=False,
                    id="editor",
                )
                yield Divider("│", id="divider")
                results = TextArea.code_editor(
                    "",
                    language=None,
                    theme="css",
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

    def on_mount(self) -> None:
        self._apply_results_width()
        editor = self.query_one("#editor", TextArea)
        if self._file_path and self._file_path.exists():
            editor.text = self._file_path.read_text(encoding="utf-8")
        editor.focus()
        self._update_banner()
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

        p = Path(path).expanduser().resolve(strict=False)
        self._file_path = p

        editor = self.query_one("#editor", TextArea)
        if p.exists():
            editor.text = p.read_text(encoding="utf-8")
        else:
            editor.text = ""
        self._update_banner()
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
        self._file_path = Path(path).expanduser().resolve(strict=False)
        self._update_banner()
        self.action_save()

    def _schedule_evaluate(self) -> None:
        if self._eval_timer is not None:
            self._eval_timer.stop()
        self._eval_timer = self.set_timer(0.15, self._evaluate_now)

    def _evaluate_now(self) -> None:
        editor = self.query_one("#editor", TextArea)
        results = self.query_one("#results", TextArea)

        user_lines = editor.text.split("\n")
        out = evaluate_source_linewise(
            build_prelude_source() + editor.text
        )
        user_outputs = out.lines[prelude_line_count():]
        if len(user_outputs) < len(user_lines):
            user_outputs = user_outputs + [""] * (len(user_lines) - len(user_outputs))
        else:
            user_outputs = user_outputs[: len(user_lines)]
        width = max(1, self._results_width - 1)
        cropped = truncate_lines(user_outputs, width)
        results.text = "\n".join(cropped)
        if round(results.scroll_y) != round(editor.scroll_y):
            results.scroll_to(y=editor.scroll_y, animate=False, immediate=True)

    def _apply_results_width(self) -> None:
        results = self.query_one("#results", TextArea)
        divider = self.query_one("#divider", Static)
        if self._results_visible:
            results.styles.display = "block"
            results.styles.width = self._results_width
            divider.styles.display = "block"
        else:
            results.styles.display = "none"
            divider.styles.display = "none"
        self.refresh(layout=True)
        self._evaluate_now()
        self._update_banner()

    def _set_results_width(self, width: int) -> None:
        self._results_width = max(MIN_RESULTS_WIDTH, min(MAX_RESULTS_WIDTH, width))
        self._apply_results_width()
        save_results_width(self._file_path, self._results_width)

    def action_widen_results(self) -> None:
        if not self._results_visible:
            self._results_visible = True
        self._set_results_width(self._results_width + self.RESIZE_STEP)

    def action_narrow_results(self) -> None:
        if not self._results_visible:
            return
        self._set_results_width(self._results_width - self.RESIZE_STEP)

    def action_toggle_results(self) -> None:
        self._results_visible = not self._results_visible
        self._apply_results_width()

    def _update_banner(self) -> None:
        banner = self.query_one("#banner", Static)

        if self._file_path is None:
            left = Text("avocado", style="#f8d66d", overflow="ellipsis", no_wrap=True)
            right = Text("", overflow="ellipsis", no_wrap=True)
        else:
            left = Text(self._file_path.name, style="#f8d66d", overflow="ellipsis", no_wrap=True)
            path_str = str(self._file_path)
            right = Text(path_str, style="#8b8d97", overflow="ellipsis", no_wrap=True)
            idx = path_str.rfind("\\")
            if idx == -1:
                idx = path_str.rfind("/")
            if idx != -1 and idx + 1 < len(path_str):
                right.stylize("#cfd0da", idx + 1, len(path_str))

        grid = Table.grid(expand=True)
        grid.add_column(ratio=1, overflow="ellipsis", no_wrap=True)
        grid.add_column(justify="right", overflow="ellipsis", no_wrap=True)
        grid.add_row(left, right)
        banner.update(grid)
