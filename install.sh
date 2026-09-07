#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-python3}"
AVOCADO_REPO="${AVOCADO_REPO:-ProtonKicker/Avocado}"
AVOCADO_REF="${AVOCADO_REF:-main}"
ZIP_URL="${AVOCADO_ZIP_URL:-https://codeload.github.com/${AVOCADO_REPO}/zip/refs/heads/${AVOCADO_REF}}"
AVOCADO_HOME="${AVOCADO_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/avocado}"
VENV_DIR="${AVOCADO_VENV_DIR:-$AVOCADO_HOME/venv}"
BIN_DIR="${AVOCADO_BIN_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
LAUNCHER_PATH="${AVOCADO_LAUNCHER_PATH:-$BIN_DIR/avocado}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "error: ${PYTHON_BIN} not found (need Python 3.10+)"
  exit 1
fi

"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1 || {
  echo "error: need Python 3.10+"
  "$PYTHON_BIN" -V || true
  exit 1
}

work_dir="$(mktemp -d)"
zip_path="$work_dir/avocado.zip"
extract_dir="$work_dir/extract"
mkdir -p "$extract_dir"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

echo "downloading: ${ZIP_URL}"
"$PYTHON_BIN" - <<PY
from __future__ import annotations
import pathlib
import urllib.request

url = ${ZIP_URL@Q}
dst = pathlib.Path(${zip_path@Q})
dst.parent.mkdir(parents=True, exist_ok=True)
urllib.request.urlretrieve(url, dst)
print(f"saved: {dst}")
PY

"$PYTHON_BIN" - <<PY
from __future__ import annotations
import pathlib
import zipfile

zip_path = pathlib.Path(${zip_path@Q})
extract_dir = pathlib.Path(${extract_dir@Q})
extract_dir.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(extract_dir)
print(f"extracted: {extract_dir}")
PY

pyproject_path="$(find "$extract_dir" -maxdepth 3 -name pyproject.toml -print -quit)"
if [[ -z "${pyproject_path}" ]]; then
  echo "error: pyproject.toml not found in downloaded zip"
  exit 1
fi
project_dir="$(dirname "$pyproject_path")"

mkdir -p "$AVOCADO_HOME" "$BIN_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install -U pip >/dev/null
"$VENV_DIR/bin/python" -m pip install -U "$project_dir" >/dev/null

cat >"$LAUNCHER_PATH" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
VENV_DIR="${AVOCADO_VENV_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/avocado/venv}"
exec "$VENV_DIR/bin/python" -B -m avocado_tui.__main__ "$@"
SH
chmod +x "$LAUNCHER_PATH"

if command -v avocado >/dev/null 2>&1; then
  avocado --help >/dev/null
  echo "ok: avocado is installed"
  exit 0
fi

echo "installed, but 'avocado' is not on PATH in this shell"
echo "add ${BIN_DIR} to PATH, open a new terminal, then run: avocado --help"
