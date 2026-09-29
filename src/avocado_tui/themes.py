from __future__ import annotations

import os
import subprocess
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


def _run(args: list[str]) -> str | None:
    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=1.0,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def _match_scheme(text: str) -> str | None:
    lowered = text.lower()
    if "dark" in lowered:
        return "dark"
    if "light" in lowered:
        return "light"
    return None


def _macos_scheme() -> str | None:
    # AppleInterfaceStyle is only written while Dark mode is active; a failed
    # read is the documented signal for Light mode.
    try:
        completed = subprocess.run(
            ["defaults", "read", "-g", "AppleInterfaceStyle"],
            capture_output=True,
            text=True,
            timeout=1.0,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return "light"
    return _match_scheme(completed.stdout) or "light"


def _windows_scheme() -> str | None:
    try:
        import winreg
    except ImportError:
        return None
    key_path = r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            value, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
    except OSError:
        return None
    return "light" if value else "dark"


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


def _linux_scheme() -> str | None:
    for args in (
        ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
        ["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
        ["kde-config", "--color-scheme"],
        ["plasma-apply-color-scheme", "--get"],
    ):
        text = _run(args)
        if text is None:
            continue
        scheme = _match_scheme(text)
        if scheme is not None:
            return scheme
    return _colorfgbg_scheme()


_DETECTORS: dict[str, Callable[[], str | None]] = {
    "darwin": _macos_scheme,
    "win32": _windows_scheme,
}


def detect_scheme() -> str:
    """Return the OS appearance as "light" or "dark". Never raises."""
    detector = _DETECTORS.get(sys.platform, _linux_scheme)
    return detector() or "dark"
