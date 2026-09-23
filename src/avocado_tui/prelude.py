from __future__ import annotations

PRELUDE_LINES: list[str] = [
    "import math",
    "import importlib.util as _avocado_importlib_util",
    'np = __import__("numpy") if _avocado_importlib_util.find_spec("numpy") is not None else None',
    "numpy = np",
    "if np is not None and not hasattr(np, 'float'): np.float = float",
    "sqrt = np.sqrt if np is not None else math.sqrt",
    "sin = np.sin if np is not None else math.sin",
    "cos = np.cos if np is not None else math.cos",
    "tan = np.tan if np is not None else math.tan",
    "asin = np.arcsin if np is not None else math.asin",
    "acos = np.arccos if np is not None else math.acos",
    "atan = np.arctan if np is not None else math.atan",
    "sinh = np.sinh if np is not None else math.sinh",
    "cosh = np.cosh if np is not None else math.cosh",
    "tanh = np.tanh if np is not None else math.tanh",
    "ln = np.log if np is not None else math.log",
    "log = np.log10 if np is not None else math.log10",
    "pi = np.pi if np is not None else math.pi",
    "e = np.e if np is not None else math.e",
]


def build_prelude_source() -> str:
    return "\n".join(PRELUDE_LINES) + "\n"


def prelude_line_count() -> int:
    return len(PRELUDE_LINES)
