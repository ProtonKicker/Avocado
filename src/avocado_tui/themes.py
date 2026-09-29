from __future__ import annotations

import os
import re
import sys
from typing import Callable

from textual.theme import Theme

DARK_VARS: dict[str, str] = {
    "canvas": "#0b0b0f",
    "ink": "#e8e8f0",
    "ink_dim": "#cfd0da",
    "muted": "#8b8d97",
    "rule": "#3a3d45",
    "rule_hover": "#5a5e69",
    "accent": "#7ec850",
    "border": "#5a5e69",
    "border-blurred": "#3a3d45",
    "input-selection-background": "#2c4a1c",
}

LIGHT_VARS: dict[str, str] = {
    "canvas": "#ffffff",
    "ink": "#16181d",
    "ink_dim": "#3a3d45",
    "muted": "#5f636c",
    "rule": "#8b8d97",
    "rule_hover": "#6b6f78",
    "accent": "#3f7d1c",
    "border": "#6b6f78",
    "border-blurred": "#b6bac4",
    "input-selection-background": "#cfe3bd",
}

DARK = Theme(
    name="avocado-dark",
    primary="#0178d4",
    secondary="#004578",
    accent=DARK_VARS["accent"],
    warning="#ffa62b",
    error="#ba3c5b",
    success="#4ebf71",
    foreground=DARK_VARS["ink"],
    background=DARK_VARS["canvas"],
    surface="#12121a",
    panel="#1a1a22",
    dark=True,
    variables=DARK_VARS,
)

LIGHT = Theme(
    name="avocado-light",
    primary="#0a5f9e",
    secondary="#0178d4",
    accent=LIGHT_VARS["accent"],
    warning="#9a5a00",
    error="#a32c44",
    success="#1e7f4f",
    foreground=LIGHT_VARS["ink"],
    background=LIGHT_VARS["canvas"],
    surface="#f5f6f8",
    panel="#eceef2",
    dark=False,
    variables=LIGHT_VARS,
)

THEMES: tuple[Theme, ...] = (DARK, LIGHT)

DARK_NAME = DARK.name
LIGHT_NAME = LIGHT.name


def theme_name_for(scheme: str) -> str:
    return LIGHT_NAME if scheme == "light" else DARK_NAME


def palette_for(name: str) -> dict[str, str]:
    return LIGHT_VARS if name == LIGHT_NAME else DARK_VARS


def _colorfgbg_scheme() -> str | None:
    # COLORFGBG is "fg;bg"; the background is what decides light vs dark.
    last = os.environ.get("COLORFGBG", "").strip().split(";")[-1].strip()
    if not last or last == "default":
        return None
    try:
        index = int(last)
    except ValueError:
        return None
    if not 0 <= index <= 15:
        return None
    return "dark" if index <= 7 else "light"


# XTerm OSC extension: ask the terminal for its default background colour.
OSC11_QUERY = "\x1b]11;?\x1b\\"
_OSC11_RGB = re.compile(
    r"\x1b\]11;rgb:([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})",
    re.ASCII,
)
_LUMA_WEIGHTS = (0.2126, 0.7152, 0.0722)
_LIGHT_THRESHOLD = 0.18


def parse_osc11(text: str) -> tuple[int, int, int] | None:
    """Return the 8-bit background colour from an OSC 11 response."""
    match = _OSC11_RGB.search(text)
    if match is None:
        return None
    components: list[int] = []
    for digits in match.groups():
        scaled = int(digits, 16) / (16 ** len(digits) - 1)
        components.append(round(scaled * 255))
    return components[0], components[1], components[2]


def scheme_from_rgb(rgb: tuple[int, int, int]) -> str:
    luminance = sum(
        weight * (value / 255) ** 2.2
        for weight, value in zip(_LUMA_WEIGHTS, rgb)
    )
    return "light" if luminance > _LIGHT_THRESHOLD else "dark"


def _response_complete(text: str) -> bool:
    match = _OSC11_RGB.search(text)
    if match is None:
        return False
    tail = text[match.end():]
    return tail.startswith("\x1b\\") or "\x07" in tail[:8]


def _scheme_from_response(text: str) -> str | None:
    rgb = parse_osc11(text)
    return None if rgb is None else scheme_from_rgb(rgb)


def _query_posix(timeout: float) -> str | None:
    import select
    import termios
    import time
    import tty

    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        return None
    fd = sys.stdin.fileno()
    try:
        attrs_before = termios.tcgetattr(fd)
    except (ValueError, OSError):
        return None
    try:
        # cbreak (not raw) so Ctrl+C keeps signalling if the terminal never
        # answers and the user gives up before the timeout.
        tty.setcbreak(fd)
        sys.stdout.write(OSC11_QUERY)
        sys.stdout.flush()
        buf = ""
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select([fd], [], [], remaining)
            if not ready:
                break
            try:
                chunk = os.read(fd, 256)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk.decode("latin-1")
            if _response_complete(buf):
                break
        return _scheme_from_response(buf)
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, attrs_before)


def _query_windows(timeout: float) -> str | None:
    import msvcrt
    import time

    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        return None
    try:
        sys.stdout.write(OSC11_QUERY)
        sys.stdout.flush()
        buf = ""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if msvcrt.kbhit():
                buf += msvcrt.getwch()
                if _response_complete(buf):
                    break
            else:
                time.sleep(0.01)
        return _scheme_from_response(buf)
    except OSError:
        return None


_QUERIES: dict[str, Callable[[float], str | None]] = {
    "win32": _query_windows,
}

QUERY_TIMEOUT_SECONDS = 0.5


def detect_scheme() -> str:
    """Return the terminal's own appearance as "light" or "dark". Never raises."""
    query = _QUERIES.get(sys.platform, _query_posix)
    try:
        scheme = query(QUERY_TIMEOUT_SECONDS)
    except Exception:
        scheme = None
    return scheme or _colorfgbg_scheme() or "dark"
