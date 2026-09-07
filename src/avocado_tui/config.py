from __future__ import annotations

import json
from pathlib import Path

CONFIG_DIR = Path.home() / ".avocado"
CONFIG_PATH = CONFIG_DIR / "config.json"

MIN_RESULTS_WIDTH = 12
MAX_RESULTS_WIDTH = 160
DEFAULT_RESULTS_WIDTH = 44


def _clamp(width: int) -> int:
    return max(MIN_RESULTS_WIDTH, min(MAX_RESULTS_WIDTH, int(width)))


def load_results_width(path: Path | None, fallback: int = DEFAULT_RESULTS_WIDTH) -> int:
    if path is None:
        return _clamp(fallback)
    try:
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return _clamp(fallback)
    widths = data.get("results_width", {})
    if not isinstance(widths, dict):
        return _clamp(fallback)
    return _clamp(widths.get(str(path), fallback))


def save_results_width(path: Path | None, width: int) -> None:
    if path is None:
        return
    try:
        try:
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            data = {}
        if not isinstance(data, dict):
            data = {}
        widths = data.setdefault("results_width", {})
        if not isinstance(widths, dict):
            widths = {}
            data["results_width"] = widths
        widths[str(path)] = _clamp(width)
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
    except OSError:
        pass
