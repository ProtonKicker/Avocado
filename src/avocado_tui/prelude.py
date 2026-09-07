from __future__ import annotations

PRELUDE_LINES: list[str] = [
    "import math",
    "from math import *",
    "import numpy",
    "import numpy as np",
]


def build_prelude_source() -> str:
    return "\n".join(PRELUDE_LINES) + "\n"


def prelude_line_count() -> int:
    return len(PRELUDE_LINES)
