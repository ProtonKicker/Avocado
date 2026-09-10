from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .math_runtime import build_math_globals
from .matlab_syntax import MathSyntaxError, TranslatedLine, translate_math_line


@dataclass(frozen=True)
class MathEvalResult:
    value: Any
    assigned_names: tuple[str, ...]


def evaluate_math_line(line: str, ns: dict[str, Any]) -> MathEvalResult:
    translated = translate_math_line(line)
    runtime_globals = build_math_globals()
    if translated.mode == "eval":
        code = compile(translated.code, "<avocado-math>", "eval")
        value = eval(code, runtime_globals, ns)
        return MathEvalResult(value=value, assigned_names=())

    code = compile(translated.code, "<avocado-math>", "exec")
    exec(code, runtime_globals, ns)
    assigned_value = None
    if len(translated.assigned_names) == 1 and translated.assigned_names[0] in ns:
        assigned_value = ns[translated.assigned_names[0]]
    return MathEvalResult(value=assigned_value, assigned_names=translated.assigned_names)


__all__ = [
    "MathEvalResult",
    "MathSyntaxError",
    "TranslatedLine",
    "evaluate_math_line",
]
