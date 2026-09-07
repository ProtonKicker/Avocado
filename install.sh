#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-python3}"
AVOCADO_REPO="${AVOCADO_REPO:-ProtonKicker/Avocado}"
AVOCADO_REF="${AVOCADO_REF:-main}"
ZIP_URL="https://github.com/${AVOCADO_REPO}/archive/refs/heads/${AVOCADO_REF}.zip"
INSTALLER_VENV="${AVOCADO_INSTALLER_VENV:-${XDG_DATA_HOME:-$HOME/.local/share}/avocado/installer-venv}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "error: ${PYTHON_BIN} not found (need Python 3.10+)"
  exit 1
fi

"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1 || {
  echo "error: need Python 3.10+"
  "$PYTHON_BIN" -V || true
  exit 1
}

echo "installing avocado from: ${ZIP_URL}"

if command -v pipx >/dev/null 2>&1; then
  pipx install --force "$ZIP_URL"
  pipx ensurepath >/dev/null 2>&1 || true
else
  echo "pipx not found; bootstrapping via venv: ${INSTALLER_VENV}"
  "$PYTHON_BIN" -m venv "$INSTALLER_VENV"
  "$INSTALLER_VENV/bin/python" -m pip install -U pip >/dev/null
  "$INSTALLER_VENV/bin/python" -m pip install -U pipx >/dev/null
  "$INSTALLER_VENV/bin/pipx" install --force "$ZIP_URL"
  "$INSTALLER_VENV/bin/pipx" ensurepath >/dev/null 2>&1 || true
fi

if command -v avocado >/dev/null 2>&1; then
  avocado --help >/dev/null
  echo "ok: avocado is installed"
  exit 0
fi

echo "installed, but 'avocado' is not on PATH in this shell"
echo "open a new terminal, then run: avocado --help"
