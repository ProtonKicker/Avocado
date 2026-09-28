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
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "$zip_path" "$ZIP_URL"
  echo "saved: $zip_path"
else
  AVOCADO_ZIP_URL="$ZIP_URL" AVOCADO_ZIP_DST="$zip_path" "$PYTHON_BIN" - <<'PY'
from __future__ import annotations
import os
import pathlib
import urllib.request

url = os.environ["AVOCADO_ZIP_URL"]
dst = pathlib.Path(os.environ["AVOCADO_ZIP_DST"])
dst.parent.mkdir(parents=True, exist_ok=True)
urllib.request.urlretrieve(url, dst)
print("saved: %s" % dst)
PY
fi

AVOCADO_ZIP_DST="$zip_path" AVOCADO_EXTRACT_DIR="$extract_dir" "$PYTHON_BIN" - <<'PY'
from __future__ import annotations
import os
import pathlib
import zipfile

zip_path = pathlib.Path(os.environ["AVOCADO_ZIP_DST"])
extract_dir = pathlib.Path(os.environ["AVOCADO_EXTRACT_DIR"])
extract_dir.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(extract_dir)
print("extracted: %s" % extract_dir)
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

# Make sure BIN_DIR is on PATH now and in future shells. Fresh macOS
# machines typically lack ~/.local/bin on PATH, so just printing
# "add it yourself" leaves `avocado: command not found`.
# Set AVOCADO_NO_MODIFY_PATH=1 to opt out of rc-file edits.
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  export PATH="$BIN_DIR:$PATH"
fi

if [[ "${AVOCADO_NO_MODIFY_PATH:-0}" != "1" ]]; then
  path_line="export PATH=\"$BIN_DIR:\$PATH\"  # added by Avocado installer"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    # Only touch files for shells that exist on this machine, plus .profile
    # as the POSIX fallback. Create the file if its shell is the current one.
    case "$rc" in
      *zshrc) command -v zsh >/dev/null 2>&1 || continue ;;
      *bashrc|*bash_profile) command -v bash >/dev/null 2>&1 || continue ;;
    esac
    if [[ -f "$rc" ]]; then
      if ! grep -Fq "$BIN_DIR" "$rc" 2>/dev/null; then
        printf '\n%s\n' "$path_line" >>"$rc"
        echo "added $BIN_DIR to PATH in $rc"
      fi
    elif [[ "$rc" == "$HOME/.zshrc" && "${SHELL:-}" == *zsh* ]] || \
         [[ "$rc" == "$HOME/.bashrc" && "${SHELL:-}" == *bash* ]] || \
         [[ "$rc" == "$HOME/.profile" ]]; then
      printf '%s\n' "$path_line" >>"$rc"
      echo "added $BIN_DIR to PATH in $rc"
    fi
  done
  # fish has its own syntax; handle it separately when fish is installed.
  if command -v fish >/dev/null 2>&1; then
    fish_conf="$HOME/.config/fish/config.fish"
    if [[ ! -f "$fish_conf" ]] || ! grep -Fq "$BIN_DIR" "$fish_conf" 2>/dev/null; then
      mkdir -p "$(dirname "$fish_conf")"
      printf '\n# added by Avocado installer\nfish_add_path %s\n' "$BIN_DIR" >>"$fish_conf"
      echo "added $BIN_DIR to PATH in $fish_conf"
    fi
  fi
fi

hash -r 2>/dev/null || true
if command -v avocado >/dev/null 2>&1; then
  avocado --help >/dev/null
  echo "ok: avocado is installed ($(command -v avocado))"
  exit 0
fi

# PATH in this non-interactive shell may still be stale even though the
# launcher exists — verify it directly as a fallback.
if [[ -x "$LAUNCHER_PATH" ]]; then
  "$LAUNCHER_PATH" --help >/dev/null
  echo "ok: avocado is installed at $LAUNCHER_PATH"
  echo "it is on PATH for new shells; for this shell run:"
  echo "  export PATH=\"$BIN_DIR:\$PATH\""
  exit 0
fi

echo "installed, but 'avocado' is not on PATH in this shell"
echo "add ${BIN_DIR} to PATH, open a new terminal, then run: avocado --help"
