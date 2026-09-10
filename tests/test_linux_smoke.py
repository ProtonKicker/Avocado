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
        demo_path = Path(__file__).resolve().parents[1] / "examples" / "demo.txt"
        app = AvocadoApp(str(demo_path))

        async with app.run_test() as pilot:
            await pilot.pause()

            editor = app.query_one("#editor", TextArea)
            results = app.query_one("#results", TextArea)

            self.assertEqual(editor.text, demo_path.read_text(encoding="utf-8"))
            self.assertIsInstance(results.text, str)

            await pilot.press("ctrl+q")


class CliPathTests(unittest.TestCase):
    def test_main_creates_missing_txt_file_before_launch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            target = Path(tmp_dir) / "nested" / "scratch.txt"
            resolved = str(target.resolve(strict=False))

            with patch.object(sys, "argv", ["avocado", str(target.with_suffix(""))]):
                with patch("avocado_tui.__main__.AvocadoApp") as app_cls:
                    main()

            self.assertTrue(target.exists())
            app_cls.assert_called_once_with(resolved)
            app_cls.return_value.run.assert_called_once_with()


class SavePathTests(unittest.IsolatedAsyncioTestCase):
    def test_resolve_user_path_uses_launch_dir_for_relative_paths(self) -> None:
        app = AvocadoApp(None)
        app._launch_dir = Path("C:/workspace/demo").resolve(strict=False)

        resolved = app._resolve_user_path("nested/file.txt")

        self.assertEqual(
            resolved, (app._launch_dir / "nested/file.txt").resolve(strict=False)
        )

    def test_resolve_user_path_keeps_absolute_paths(self) -> None:
        app = AvocadoApp(None)
        absolute = Path("C:/temp/output.txt").resolve(strict=False)

        resolved = app._resolve_user_path(str(absolute))

        self.assertEqual(resolved, absolute)

    def test_ensure_txt_path_rewrites_non_txt_suffixes(self) -> None:
        app = AvocadoApp(None)

        self.assertEqual(app._ensure_txt_path("notes"), "notes.txt")
        self.assertEqual(app._ensure_txt_path("notes.py"), "notes.txt")
        self.assertEqual(app._ensure_txt_path("notes.txt"), "notes.txt")

    async def test_save_as_callback_creates_parent_dirs_and_writes_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            app = AvocadoApp(None)
            app._launch_dir = Path(tmp_dir).resolve(strict=False)

            async with app.run_test() as pilot:
                await pilot.pause()
                editor = app.query_one("#editor", TextArea)
                editor.text = "value = int(3.14)\nvalue"

                app._save_as_callback("nested/saved.py")

                target = app._launch_dir / "nested" / "saved.txt"
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


class MixedGrammarTests(unittest.TestCase):
    def test_math_aliases_and_python_assignments_share_namespace(self) -> None:
        source = build_prelude_source() + "x = 3\ny = e^x\nz = sin(pi / 2) + x\n"
        out = evaluate_source_linewise(source)

        self.assertEqual(out.namespace["x"], 3)
        self.assertAlmostEqual(float(out.namespace["y"]), 20.085536923187668)
        self.assertAlmostEqual(float(out.namespace["z"]), 4.0)

    def test_matlab_range_and_matrix_literals(self) -> None:
        source = build_prelude_source() + "r = 1:1:5\nm = [1 2 3; 4 5 6]\n"
        out = evaluate_source_linewise(source)

        self.assertEqual(out.namespace["r"].tolist(), [1, 2, 3, 4, 5])
        self.assertEqual(out.namespace["m"].shape, (2, 3))

    def test_python_lists_and_indexing_still_work(self) -> None:
        source = build_prelude_source() + "items = [1, 2, 3]\nitems[1]\n"
        out = evaluate_source_linewise(source)

        user_lines = out.lines[prelude_line_count():]
        self.assertEqual(out.namespace["items"], [1, 2, 3])
        self.assertEqual(user_lines[:2], ["[1, 2, 3]", "2"])
