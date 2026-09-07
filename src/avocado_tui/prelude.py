from __future__ import annotations

PRELUDE_LINES: list[str] = [
    "import math",
    "from math import *",
    "import importlib.util as _avocado_importlib_util",
    'np = __import__("numpy") if _avocado_importlib_util.find_spec("numpy") is not None else None',
    "numpy = np",
]


def build_prelude_source() -> str:
    return "\n".join(PRELUDE_LINES) + "\n"


def prelude_line_count() -> int:
    return len(PRELUDE_LINES)
