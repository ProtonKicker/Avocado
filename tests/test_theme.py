from __future__ import annotations

import re
import unittest
from subprocess import CompletedProcess
from unittest.mock import patch

from textual.color import Color
from textual.widgets import Input, TextArea

from avocado_tui import themes
from avocado_tui.app import AvocadoApp, PathPromptScreen


def _css_variables(*sources: str) -> set[str]:
    found: set[str] = set()
    for source in sources:
        found.update(re.findall(r"\$([a-zA-Z0-9_\-]+)", source))
    return found


class PaletteTests(unittest.TestCase):
    def test_both_palettes_define_identical_keys(self) -> None:
        # An undefined $var fails CSS parsing outright, so parity is required.
        self.assertEqual(set(themes.DARK_VARS), set(themes.LIGHT_VARS))
        self.assertEqual(set(themes.DARK_VARS), set(themes.palette_for(themes.LIGHT_NAME)))

    def test_every_css_variable_resolves_in_both_themes(self) -> None:
        referenced = _css_variables(AvocadoApp.CSS, PathPromptScreen.CSS)
        self.assertTrue(referenced)
        app = AvocadoApp(None)
        available = (
            set(themes.DARK_VARS)
            | set(themes.LIGHT_VARS)
            | set(app.get_theme_variable_defaults())
        )
        self.assertEqual(referenced - available, set())

    def test_app_css_has_no_hardcoded_colors_left(self) -> None:
        for source in (AvocadoApp.CSS, PathPromptScreen.CSS):
            self.assertNotIn("#0b0b0f", source)
            self.assertNotIn("#7ec850", source)
            self.assertNotIn("#8b8d97", source)


class DetectSchemeTests(unittest.TestCase):
    def _fake_run(self, returncode: int, stdout: str):
        def runner(args, **kwargs):
            return CompletedProcess(args, returncode, stdout, "")

        return runner

    def test_macos_returns_none_when_defaults_is_unavailable(self) -> None:
        with patch(
            "avocado_tui.themes.subprocess.run",
            side_effect=FileNotFoundError("defaults not found"),
        ):
            self.assertIsNone(themes._macos_scheme())

    def test_macos_reads_dark(self) -> None:
        with patch(
            "avocado_tui.themes.subprocess.run",
            side_effect=self._fake_run(0, "Dark\n"),
        ):
            self.assertEqual(themes._macos_scheme(), "dark")

    def test_macos_reads_light_when_defaults_exits_nonzero(self) -> None:
        with patch(
            "avocado_tui.themes.subprocess.run",
            side_effect=self._fake_run(1, ""),
        ):
            self.assertEqual(themes._macos_scheme(), "light")

    def test_macos_failure_never_raises(self) -> None:
        with patch(
            "avocado_tui.themes.subprocess.run",
            side_effect=OSError("boom"),
        ):
            self.assertIsNone(themes._macos_scheme())

    def test_colorfgbg_uses_background_field(self) -> None:
        cases = {"15;0": "dark", "0;15": "light", "7;8": "light", "15;default": None}
        for value, expected in cases.items():
            with self.subTest(value=value), patch.dict(
                themes.os.environ, {"COLORFGBG": value}, clear=False
            ):
                self.assertEqual(themes._colorfgbg_scheme(), expected)

    def test_colorfgbg_garbage_is_ignored(self) -> None:
        with patch.dict(themes.os.environ, {"COLORFGBG": ""}, clear=False):
            self.assertIsNone(themes._colorfgbg_scheme())

    def test_detect_scheme_falls_back_to_dark(self) -> None:
        with patch("avocado_tui.themes.sys.platform", "linux"), patch(
            "avocado_tui.themes._linux_scheme", return_value=None
        ):
            self.assertEqual(themes.detect_scheme(), "dark")

    def test_theme_name_mapping(self) -> None:
        self.assertEqual(themes.theme_name_for("light"), themes.LIGHT_NAME)
        self.assertEqual(themes.theme_name_for("dark"), themes.DARK_NAME)


class AppThemeTests(unittest.IsolatedAsyncioTestCase):
    async def test_initial_theme_follows_detection(self) -> None:
        with patch("avocado_tui.app.detect_scheme", return_value="light"):
            app = AvocadoApp(None)
            self.assertEqual(app.theme, themes.LIGHT_NAME)
            async with app.run_test() as pilot:
                await pilot.pause()
                self.assertEqual(app.screen.styles.background, Color(255, 255, 255))
                await pilot.press("ctrl+q")

    async def test_dark_theme_keeps_the_original_canvas(self) -> None:
        with patch("avocado_tui.app.detect_scheme", return_value="dark"):
            app = AvocadoApp(None)
            self.assertEqual(app.theme, themes.DARK_NAME)
            async with app.run_test() as pilot:
                await pilot.pause()
                self.assertEqual(app.screen.styles.background, Color(11, 11, 15))
                await pilot.press("ctrl+q")

    async def test_both_text_areas_paint_the_canvas_not_surface(self) -> None:
        # TextArea DEFAULT_CSS is `background: $surface`, so #editor/#results
        # must set $canvas explicitly or the panels sit in lighter boxes.
        with patch("avocado_tui.app.detect_scheme", return_value="light"):
            app = AvocadoApp(None)
            async with app.run_test() as pilot:
                await pilot.pause()
                for selector in ("#editor", "#results"):
                    widget = app.query_one(selector, TextArea)
                    self.assertEqual(
                        widget.styles.background,
                        Color(255, 255, 255),
                        f"{selector} lost its explicit canvas background",
                    )
                await pilot.press("ctrl+q")

    async def test_theme_switches_live_when_appearance_changes(self) -> None:
        detected = {"scheme": "light"}
        with patch(
            "avocado_tui.app.detect_scheme", side_effect=lambda: detected["scheme"]
        ):
            app = AvocadoApp(None)
            async with app.run_test() as pilot:
                await pilot.pause()
                self.assertEqual(app.theme, themes.LIGHT_NAME)
                self.assertEqual(app.screen.styles.background, Color(255, 255, 255))
                self.assertEqual(app._accent, themes.LIGHT_VARS["accent"])

                # Let the follow-the-system interval notice the change on its own.
                detected["scheme"] = "dark"
                await pilot.pause(2.5)

                self.assertEqual(app.theme, themes.DARK_NAME)
                self.assertEqual(app.screen.styles.background, Color(11, 11, 15))
                self.assertEqual(app._accent, themes.DARK_VARS["accent"])
                self.assertEqual(app._muted, themes.DARK_VARS["muted"])

                detected["scheme"] = "light"
                await pilot.pause(2.5)
                self.assertEqual(app.theme, themes.LIGHT_NAME)
                self.assertEqual(app.screen.styles.background, Color(255, 255, 255))
                await pilot.press("ctrl+q")

    async def test_sync_is_a_noop_when_scheme_unchanged(self) -> None:
        with patch("avocado_tui.app.detect_scheme", return_value="light"):
            app = AvocadoApp(None)
            async with app.run_test() as pilot:
                await pilot.pause()
                app._sync_theme_to_system()
                app._sync_theme_to_system()
                await pilot.pause()
                self.assertEqual(app.theme, themes.LIGHT_NAME)
                await pilot.press("ctrl+q")

    async def test_banner_rich_styles_use_the_active_palette(self) -> None:
        # Drive the palette through detect_scheme so the follow-the-system
        # interval agrees with the theme under test instead of reverting it.
        detected = {"scheme": "light"}
        with patch(
            "avocado_tui.app.detect_scheme", side_effect=lambda: detected["scheme"]
        ):
            app = AvocadoApp("/tmp/demo.txt")
            async with app.run_test() as pilot:
                await pilot.pause()

                def banner_colors():
                    spans = app.query_one("#banner").render().spans
                    return {span.style.foreground for span in spans}

                light_accent = Color.parse(themes.LIGHT_VARS["accent"])
                dark_accent = Color.parse(themes.DARK_VARS["accent"])
                self.assertIn(light_accent, banner_colors())
                self.assertNotIn(dark_accent, banner_colors())

                detected["scheme"] = "dark"
                app._sync_theme_to_system()
                await pilot.pause()
                await pilot.pause()
                self.assertIn(dark_accent, banner_colors())
                self.assertNotIn(light_accent, banner_colors())
                await pilot.press("ctrl+q")

    async def test_path_dialog_is_readable_on_light_canvas(self) -> None:
        with patch("avocado_tui.app.detect_scheme", return_value="light"):
            app = AvocadoApp(None)
            async with app.run_test() as pilot:
                await pilot.pause()
                app.action_new_file()
                await pilot.pause()
                await pilot.pause()
                screen = app.screen
                self.assertIsInstance(screen, PathPromptScreen)
                box = screen.query_one(Input)
                self.assertEqual(box.styles.background, Color(255, 255, 255))
                # border.top is a ("tall", Color) pair
                border_color = box.styles.border.top[1]
                self.assertNotEqual(
                    border_color,
                    Color(255, 255, 255),
                    "input border is invisible on the white canvas",
                )
                self.assertLess(border_color.brightness, 0.8)
                self.assertIn(
                    border_color.hex.lower(),
                    {themes.LIGHT_VARS["border"], themes.LIGHT_VARS["border-blurred"]},
                )
                await pilot.press("escape")
                await pilot.press("ctrl+q")


if __name__ == "__main__":
    unittest.main()
