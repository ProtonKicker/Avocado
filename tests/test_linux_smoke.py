from __future__ import annotations

import sys
import tempfile
import unittest
from importlib import util as importlib_util
from pathlib import Path
from unittest.mock import patch

from textual.widgets import TextArea

from avocado_tui.__main__ import main
from avocado_tui.app import AvocadoApp
from avocado_tui.evaluator import evaluate_source_linewise
from avocado_tui.prelude import build_prelude_source, prelude_line_count


class LinuxSmokeTests(unittest.IsolatedAsyncioTestCase):
    async def test_app_boots_and_renders_demo_file(self) -> None:
        demo_path = Path(__file__).resolve().parents[1] / "examples" / "demo.py"
        app = AvocadoApp(str(demo_path))

        async with app.run_test() as pilot:
            await pilot.pause()

            editor = app.query_one("#editor", TextArea)
            results = app.query_one("#results", TextArea)

            self.assertEqual(editor.text, demo_path.read_text(encoding="utf-8"))
            self.assertIsInstance(results.text, str)

            await pilot.press("ctrl+q")


class CliPathTests(unittest.TestCase):
    def test_main_creates_missing_file_before_launch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            target = Path(tmp_dir) / "nested" / "scratch.py"
            resolved = str(target.resolve(strict=False))

            with patch.object(sys, "argv", ["avocado", str(target)]):
                with patch("avocado_tui.__main__.AvocadoApp") as app_cls:
                    main()

            self.assertTrue(target.exists())
            app_cls.assert_called_once_with(resolved)
            app_cls.return_value.run.assert_called_once_with()


class SavePathTests(unittest.IsolatedAsyncioTestCase):
    def test_resolve_user_path_uses_launch_dir_for_relative_paths(self) -> None:
        app = AvocadoApp(None)
        app._launch_dir = Path("C:/workspace/demo").resolve(strict=False)

        resolved = app._resolve_user_path("nested/file.py")

        self.assertEqual(
            resolved, (app._launch_dir / "nested/file.py").resolve(strict=False)
        )

    def test_resolve_user_path_keeps_absolute_paths(self) -> None:
        app = AvocadoApp(None)
        absolute = Path("C:/temp/output.py").resolve(strict=False)

        resolved = app._resolve_user_path(str(absolute))

        self.assertEqual(resolved, absolute)

    async def test_save_as_callback_creates_parent_dirs_and_writes_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            app = AvocadoApp(None)
            app._launch_dir = Path(tmp_dir).resolve(strict=False)

            async with app.run_test() as pilot:
                await pilot.pause()
                editor = app.query_one("#editor", TextArea)
                editor.text = "value = int(3.14)\nvalue"

                app._save_as_callback("nested/saved.py")

                target = app._launch_dir / "nested" / "saved.py"
                self.assertEqual(app._file_path, target.resolve(strict=False))
                self.assertTrue(target.exists())
                self.assertEqual(target.read_text(encoding="utf-8"), editor.text)

                await pilot.press("ctrl+q")


class PreludeTests(unittest.TestCase):
    def test_missing_numpy_does_not_skip_user_code(self) -> None:
        original_find_spec = importlib_util.find_spec

        def fake_find_spec(name: str, package: str | None = None):
            if name == "numpy":
                return None
            return original_find_spec(name, package)

        with patch("importlib.util.find_spec", side_effect=fake_find_spec):
            source = build_prelude_source() + "aa = 1\nnp\n"
            out = evaluate_source_linewise(source)

        user_lines = out.lines[prelude_line_count():]
        self.assertEqual(user_lines[:2], ["1", "None"])
