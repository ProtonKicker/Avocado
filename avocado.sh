#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PY="$REPO_ROOT/.venv/bin/python"

if [[ ! -x "$VENV_PY" ]]; then
  python3 -m venv "$REPO_ROOT/.venv"
  "$VENV_PY" -m pip install -U pip
  "$VENV_PY" -m pip install -e "$REPO_ROOT"
fi

export PYTHONDONTWRITEBYTECODE=1
"$VENV_PY" -B -m avocado_tui.__main__ "${1:-}"

