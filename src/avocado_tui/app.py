from __future__ import annotations

from pathlib import Path
from typing import Optional

from rich.cells import cell_len
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


ACCENT = "#7ec850"
TOOLBAR_LABEL = "ctrl+q quit  ctrl+n new  ctrl+s save  ctrl+r results"
MIN_WINDOW_WIDTH = cell_len(f" {TOOLBAR_LABEL} ")
MIN_LEFT_PANEL_WIDTH = (MIN_WINDOW_WIDTH + 1) // 2
TEXTAREA_FRAME_WIDTH = 2
MIN_EDITOR_WIDGET_WIDTH = MIN_LEFT_PANEL_WIDTH + TEXTAREA_FRAME_WIDTH
MIN_WINDOW_HEIGHT = 7
MIN_CONTENT_HEIGHT = 5


class PathPromptScreen(ModalScreen[Optional[str]]):
    BINDINGS = [("escape", "cancel", "Cancel")]
    CSS = """
    PathPromptScreen {
        align: left top;
        padding: 1 1 0 1;
    }

    #path-dialog {
        width: 100%;
        padding: 1 2;
        background: transparent;
    }

    #path-title {
        color: #7ec850;
        text-style: bold;
        margin-bottom: 1;
    }

    #path-help {
        color: #8b8d97;
        margin-top: 1;
        width: 100%;
        content-align: right middle;
    }

    #path-submit {
        color: #8b8d97;
        margin-top: 1;
    }

    #path-cancel {
        color: #8b8d97;
    }

    #path {
        width: 100%;
    }
    """

    def __init__(
        self,
        initial_path: str = "",
        title: str = "Enter file path",
        placeholder: str = "Enter file path…",
        path_help_text: str = "",
        submit_text: str = "Enter=confirm",
        cancel_text: str = "Esc=cancel",
    ) -> None:
        super().__init__()
        self._initial_path = initial_path
        self._title = title
        self._placeholder = placeholder
        self._path_help_text = path_help_text
        self._submit_text = submit_text
        self._cancel_text = cancel_text

    def compose(self) -> ComposeResult:
        with Vertical(id="path-dialog"):
            yield Static(self._title, id="path-title")
            yield Input(value=self._initial_path, placeholder=self._placeholder, id="path")
            yield Static(self._path_help_text, id="path-help")
            yield Static(self._submit_text, id="path-submit")
            yield Static(self._cancel_text, id="path-cancel")

    def on_mount(self) -> None:
        input_widget = self.query_one(Input)
        input_widget.focus()
        input_widget.cursor_position = len(input_widget.value)

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


class Banner(Static):
    def on_mouse_down(self, event: events.MouseDown) -> None:
        app = self.app
        if not isinstance(app, AvocadoApp):
            return
        if app._file_path is None:
            return
        if event.y != 0:
            return

        w = self.size.width
        if w <= 0:
            return

        if event.x < app._banner_right_start_x:
            return

        file_name = app._file_path.name
        if not app._banner_path_visible:
            app.copy_to_clipboard(file_name)
            return

        if event.x >= app._banner_filename_start_x:
            app.copy_to_clipboard(file_name)
        else:
            app.copy_to_clipboard(str(app._file_path))


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
        max_results_width = max(
            MIN_RESULTS_WIDTH, screen_w - MIN_EDITOR_WIDGET_WIDTH - 1
        )
        app._results_width = max(
            MIN_RESULTS_WIDTH, min(MAX_RESULTS_WIDTH, max_results_width, new_width)
        )
        results.styles.width = app._results_width
        app.refresh(layout=True)
        app._evaluate_now()

    def render(self) -> Text:
        height = self.size.height
        if height <= 1:
            return Text("│")
        return Text("\n".join(["│"] * height))


class HorizontalSplit(Static):
    """Full-width horizontal split line with a right-aligned label.

    Renders a line of box-drawing characters across the screen with the
    label integrated on the right edge, similar to Mistral Vibe's
    "accept edits" line.
    """

    def __init__(self, label: str = "", **kwargs) -> None:
        super().__init__("", **kwargs)
        self._label = label

    def set_label(self, label: str) -> None:
        self._label = label
        self.refresh()

    def render(self) -> Text:
        width = self.size.width
        if width <= 0:
            return Text("")
        line_char = "─"
        text = Text()
        if not self._label:
            text.append(line_char * width)
            return text
        label_part = f" {self._label} "
        label_text = Text(label_part, style="bold", no_wrap=True)
        if label_text.cell_len >= width:
            label_text.truncate(width, overflow="ellipsis")
            return label_text
        line_len = max(0, width - label_text.cell_len)
        text.append(line_char * line_len)
        text.append_text(label_text)
        return text


class AvocadoApp(App):
    CSS = """
    Screen {{
        background: #0b0b0f;
        color: #e8e8f0;
    }}

    #banner {{
        height: 1;
        padding: 0 1;
        color: #cfd0da;
        background: #0b0b0f;
        overflow: hidden hidden;
        text-wrap: nowrap;
        text-overflow: clip;
    }}

    #hsplit {{
        height: 1;
        background: #0b0b0f;
        color: #3a3d45;
    }}

    #toolbar {{
        height: 1;
        background: #0b0b0f;
        color: #3a3d45;
    }}

    #body {{
        height: 1fr;
    }}

    #editor {{
        width: 1fr;
        min-width: {min_editor_widget_width};
        height: 100%;
        border: none;
        background: #0b0b0f;
    }}

    #divider {{
        width: 1;
        height: 100%;
        background: #0b0b0f;
        color: #3a3d45;
    }}

    #divider:hover {{
        background: #0b0b0f;
        color: #5a5e69;
    }}

    #divider.-dragging {{
        background: #0b0b0f;
        color: #7ec850;
    }}

    #results {{
        width: 44;
        height: 100%;
        border: none;
        background: #0b0b0f;
        color: #cfd0da;
    }}

    """.format(
        min_editor_widget_width=MIN_EDITOR_WIDGET_WIDTH,
    )

    BINDINGS = [
        ("ctrl+q", "quit", "Quit"),
        ("ctrl+n", "new_file", "New file"),
        ("ctrl+s", "save", "Save"),
        ("ctrl+r", "toggle_results", "Toggle results"),
    ]

    def __init__(self, file_path: str | None = None) -> None:
        super().__init__()
        self._launch_dir = Path.cwd().resolve(strict=False)
        self._file_path = (
            Path(file_path).expanduser().resolve(strict=False) if file_path else None
        )
        self._eval_timer: Timer | None = None
        self._results_width: int = load_results_width(self._file_path)
        self._dragging = False
        self._results_visible = True
        self._banner_path_visible = True
        self._banner_right_start_x = 0
        self._banner_filename_start_x = 0

    def compose(self) -> ComposeResult:
        with Vertical():
            yield Banner("", id="banner")
            yield HorizontalSplit(id="hsplit")
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
            yield HorizontalSplit(
                TOOLBAR_LABEL,
                id="toolbar",
            )

    def on_mount(self) -> None:
        self._apply_results_width()
        editor = self.query_one("#editor", TextArea)
        if self._file_path and self._file_path.exists():
            editor.text = self._file_path.read_text(encoding="utf-8")
        editor.focus()
        self._update_banner()
        self.call_later(self._update_banner)
        self._evaluate_now()

    def on_text_area_changed(self, event: TextArea.Changed) -> None:
        if event.text_area.id != "editor":
            return
        self._schedule_evaluate()

    async def _on_resize(self, event: events.Resize) -> None:
        await super()._on_resize(event)
        self._evaluate_now()
        self._update_banner()
        self.call_later(self._update_banner)

    def action_new_file(self) -> None:
        base_dir = self._file_path.parent if self._file_path else self._launch_dir
        suggested = str(base_dir / "untitled.py")
        self.push_screen(
            PathPromptScreen(
                suggested,
                title="Enter file name and path",
                placeholder="path\\to\\untitled.py",
                path_help_text=f"Relative paths start from {self._launch_dir}",
                submit_text="Enter=create",
                cancel_text="Esc=cancel",
            ),
            self._new_file_callback,
        )

    def _new_file_callback(self, path: Optional[str]) -> None:
        if not path:
            return

        self._file_path = self._resolve_user_path(path)
        editor = self.query_one("#editor", TextArea)
        editor.text = ""
        editor.focus()
        self._update_banner()
        self._evaluate_now()

    def action_save(self) -> None:
        suggested = str(self._file_path or (self._launch_dir / "untitled.py"))
        self.push_screen(
            PathPromptScreen(
                suggested,
                title="Enter file name and path",
                placeholder="path\\to\\file.py",
                path_help_text=f"Relative paths start from {self._launch_dir}",
                submit_text="Enter=save",
                cancel_text="Esc=cancel",
            ),
            self._save_as_callback,
        )

    def _save_as_callback(self, path: Optional[str]) -> None:
        if not path:
            return
        self._file_path = self._resolve_user_path(path)
        self._update_banner()
        editor = self.query_one("#editor", TextArea)
        self._file_path.parent.mkdir(parents=True, exist_ok=True)
        self._file_path.write_text(editor.text, encoding="utf-8")

    def _resolve_user_path(self, raw_path: str) -> Path:
        path = Path(raw_path.strip()).expanduser()
        if path.is_absolute():
            return path.resolve(strict=False)
        return (self._launch_dir / path).resolve(strict=False)

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
        max_results_width = max(
            MIN_RESULTS_WIDTH, self.size.width - MIN_EDITOR_WIDGET_WIDTH - 1
        )
        self._results_width = max(
            MIN_RESULTS_WIDTH, min(MAX_RESULTS_WIDTH, max_results_width, self._results_width)
        )
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

    def action_toggle_results(self) -> None:
        self._results_visible = not self._results_visible
        self._apply_results_width()

    def _truncate_banner_text(self, text: str, width: int) -> str:
        if width <= 0:
            return ""
        if cell_len(text) <= width:
            return text
        if width == 1:
            return "…"
        return text[: width - 1] + "…"

    def _truncate_filename(self, file_name: str, width: int) -> str:
        if width <= 0:
            return ""
        if cell_len(file_name) <= width:
            return file_name
        suffix = Path(file_name).suffix
        if suffix and cell_len(suffix) + 2 <= width:
            prefix_w = width - cell_len(suffix) - 1
            return file_name[:prefix_w] + "…" + suffix
        return self._truncate_banner_text(file_name, width)

    def _update_banner(self) -> None:
        banner = self.query_one("#banner", Static)
        content_w = max(1, banner.content_region.width, self.size.width - 2)
        app_name = "Avocado"
        app_name_w = cell_len(app_name)

        first_line = Text(no_wrap=True)

        if self._file_path is None:
            first_line.append(app_name, style=ACCENT)
            self._banner_right_start_x = content_w
            self._banner_filename_start_x = content_w
            self._banner_path_visible = False
        else:
            path_str = str(self._file_path)
            file_name = self._file_path.name
            available_right_w = max(1, content_w - (app_name_w + 2))
            self._banner_path_visible = cell_len(path_str) <= max(0, available_right_w - 1)

            if self._banner_path_visible:
                right_display = path_str
            else:
                right_display = self._truncate_filename(file_name, available_right_w)
            right_display_w = cell_len(right_display)
            right_display_used_w = min(available_right_w, right_display_w) + 1
            gap_w = max(1, content_w - app_name_w - right_display_used_w)

            first_line.append(app_name, style=ACCENT)
            first_line.append(" " * gap_w)
            self._banner_right_start_x = app_name_w + gap_w

            if self._banner_path_visible:
                first_line.append(right_display, style="#8b8d97")
                idx = right_display.rfind("\\")
                if idx == -1:
                    idx = right_display.rfind("/")
                if idx != -1 and idx + 1 < len(right_display):
                    self._banner_filename_start_x = self._banner_right_start_x + idx + 1
                    first_line.stylize(
                        ACCENT,
                        self._banner_filename_start_x,
                        self._banner_right_start_x + len(right_display),
                    )
                else:
                    self._banner_filename_start_x = self._banner_right_start_x
            else:
                self._banner_filename_start_x = self._banner_right_start_x
                first_line.append(right_display, style=ACCENT)
            first_line.append(" ")

        if first_line.cell_len < content_w:
            first_line.append(" " * (content_w - first_line.cell_len))

        banner.update(first_line)
