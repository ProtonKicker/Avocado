from __future__ import annotations

import re
import unittest
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
    def test_parse_osc11_reads_16_bit_components(self) -> None:
        response = "\x1b]11;rgb:ffff/ffff/0000\x1b\\"
        self.assertEqual(themes.parse_osc11(response), (255, 255, 0))

    def test_parse_osc11_reads_8_bit_and_uppercase(self) -> None:
        self.assertEqual(themes.parse_osc11("\x1b]11;rgb:FF/FF/FF\x07"), (255, 255, 255))

    def test_parse_osc11_ignores_junk(self) -> None:
        for text in ("", "\x1b[?1;2c", "\x1b]11;rgb:zz/00/00\x1b\\", "rgb:00/00/00"):
            with self.subTest(text=text):
                self.assertIsNone(themes.parse_osc11(text))

    def test_response_complete_requires_terminator(self) -> None:
        self.assertTrue(themes._response_complete("\x1b]11;rgb:00/00/00\x1b\\"))
        self.assertTrue(themes._response_complete("\x1b]11;rgb:00/00/00\x07"))
        self.assertFalse(themes._response_complete("\x1b]11;rgb:00/00/00"))

    def test_scheme_from_rgb_luminance(self) -> None:
        cases = {
            (255, 255, 255): "light",
            (0, 0, 0): "dark",
            (46, 52, 54): "dark",     # typical dark-theme canvas
            (128, 128, 128): "light",  # mid grey reads as a light terminal
            (250, 245, 235): "light",  # paper-like light theme
            (30, 30, 30): "dark",
        }
        for rgb, expected in cases.items():
            with self.subTest(rgb=rgb):
                self.assertEqual(themes.scheme_from_rgb(rgb), expected)

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

    def test_detect_scheme_prefers_terminal_answer(self) -> None:
        with patch("avocado_tui.themes._query_posix", return_value="light"), patch.dict(
            themes.os.environ, {"COLORFGBG": "15;0"}, clear=False
        ):
            self.assertEqual(themes.detect_scheme(), "light")

    def test_detect_scheme_falls_back_to_colorfgbg(self) -> None:
        with patch("avocado_tui.themes._query_posix", return_value=None), patch.dict(
            themes.os.environ, {"COLORFGBG": "0;15"}, clear=False
        ):
            self.assertEqual(themes.detect_scheme(), "light")

    def test_detect_scheme_falls_back_to_dark(self) -> None:
        with patch("avocado_tui.themes._query_posix", return_value=None), patch.dict(
            themes.os.environ, {"COLORFGBG": ""}, clear=False
        ):
            self.assertEqual(themes.detect_scheme(), "dark")

    def test_detect_scheme_never_raises(self) -> None:
        with patch("avocado_tui.themes._query_posix", side_effect=OSError("boom")), patch.dict(
            themes.os.environ, {"COLORFGBG": ""}, clear=False
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

    async def test_theme_can_be_switched_at_runtime(self) -> None:
        with patch("avocado_tui.app.detect_scheme", return_value="light"):
            app = AvocadoApp(None)
            async with app.run_test() as pilot:
                await pilot.pause()
                self.assertEqual(app.theme, themes.LIGHT_NAME)
                app.theme = themes.DARK_NAME
                await pilot.pause()
                self.assertEqual(app.screen.styles.background, Color(11, 11, 15))
                self.assertEqual(app._accent, themes.DARK_VARS["accent"])
                self.assertEqual(app._muted, themes.DARK_VARS["muted"])
                await pilot.press("ctrl+q")

    async def test_banner_rich_styles_use_the_active_palette(self) -> None:
        with patch("avocado_tui.app.detect_scheme", return_value="light"):
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

                app.theme = themes.DARK_NAME
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
