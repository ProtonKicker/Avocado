from __future__ import annotations

import math
from typing import Any

import numpy as np

from .math_constants import CONSTANT_ALIASES, SCIENTIFIC_CONSTANTS


def ln(value: Any) -> Any:
    return np.log(value)


def arcsin(value: Any) -> Any:
    return np.arcsin(value)


def arccos(value: Any) -> Any:
    return np.arccos(value)


def arctan(value: Any) -> Any:
    return np.arctan(value)


def matlab_range(start: Any, stop: Any, step: Any | None = None) -> np.ndarray:
    start_f = float(start)
    stop_f = float(stop)
    if step is None:
        step_f = 1.0 if stop_f >= start_f else -1.0
    else:
        step_f = float(step)
    if step_f == 0:
        raise ValueError("MATLAB range step cannot be zero")

    values: list[float] = []
    current = start_f
    epsilon = abs(step_f) * 1e-9 + 1e-12
    if step_f > 0:
        while current <= stop_f + epsilon:
            values.append(current)
            current += step_f
    else:
        while current >= stop_f - epsilon:
            values.append(current)
            current += step_f
    return np.array(values)


def zeros(*shape: int) -> np.ndarray:
    return np.zeros(shape or (1,))


def ones(*shape: int) -> np.ndarray:
    return np.ones(shape or (1,))


def eye(size: int) -> np.ndarray:
    return np.eye(size)


def size(value: Any) -> tuple[int, ...]:
    return tuple(np.shape(value))


def length(value: Any) -> int:
    arr = np.asarray(value)
    if arr.ndim == 0:
        return 1
    return int(max(arr.shape))


def build_math_globals() -> dict[str, Any]:
    env: dict[str, Any] = {
        "__builtins__": __builtins__,
        "math": math,
        "np": np,
        "numpy": np,
        "ln": ln,
        "log": np.log10,
        "sqrt": np.sqrt,
        "sin": np.sin,
        "cos": np.cos,
        "tan": np.tan,
        "asin": np.arcsin,
        "acos": np.arccos,
        "atan": np.arctan,
        "arcsin": arcsin,
        "arccos": arccos,
        "arctan": arctan,
        "sinh": np.sinh,
        "cosh": np.cosh,
        "tanh": np.tanh,
        "matlab_range": matlab_range,
        "zeros": zeros,
        "ones": ones,
        "eye": eye,
        "linspace": np.linspace,
        "size": size,
        "length": length,
        "sum": np.sum,
    }
    env.update(SCIENTIFIC_CONSTANTS)
    for alias, target in CONSTANT_ALIASES.items():
        env[alias] = env[target]
    return env
