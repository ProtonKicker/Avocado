#!/usr/bin/env bash
set -euo pipefail

ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
AVOCADO_REPO="${AVOCADO_REPO:-ProtonKicker/Avocado}"
AVOCADO_REF="${AVOCADO_REF:-main}"
ZIP_URL="${AVOCADO_ZIP_URL:-https://codeload.github.com/${AVOCADO_REPO}/zip/refs/heads/${AVOCADO_REF}}"
AVOCADO_HOME="${AVOCADO_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/avocado}"
REPO_DIR="${AVOCADO_REPO_DIR:-$AVOCADO_HOME/repo}"
INSTALL_DIR="${AVOCADO_INSTALL_DIR:-$AVOCADO_HOME/install}"
BIN_DIR="${AVOCADO_BIN_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
LAUNCHER_PATH="${AVOCADO_LAUNCHER_PATH:-$BIN_DIR/avocado}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${AVOCADO_SOURCE_DIR:-}"

if [[ -z "${SOURCE_DIR}" && -f "${SCRIPT_DIR}/build.zig" && -d "${SCRIPT_DIR}/src" ]]; then
  SOURCE_DIR="${SCRIPT_DIR}"
fi

if [[ -z "${ZIG_BIN}" ]]; then
  echo "error: zig not found (need Zig 0.16+)"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl not found"
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "error: unzip not found"
  exit 1
fi

work_dir=""
cleanup() {
  if [[ -n "${work_dir}" && -d "${work_dir}" ]]; then
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$AVOCADO_HOME" "$BIN_DIR"
rm -rf "$INSTALL_DIR"

if [[ -n "${SOURCE_DIR}" ]]; then
  echo "installing from local source: ${SOURCE_DIR}"
  repo_build_dir="${SOURCE_DIR}"
else
  rm -rf "$REPO_DIR"
  work_dir="$(mktemp -d)"
  zip_path="$work_dir/avocado.zip"
  extract_dir="$work_dir/extract"
  mkdir -p "$extract_dir"

  echo "downloading: ${ZIP_URL}"
  curl -fsSL "$ZIP_URL" -o "$zip_path"
  unzip -q "$zip_path" -d "$extract_dir"

  build_path="$(find "$extract_dir" -maxdepth 3 -name build.zig -print -quit)"
  if [[ -z "${build_path}" ]]; then
    echo "error: build.zig not found in downloaded zip"
    exit 1
  fi
  project_dir="$(dirname "$build_path")"
  mv "$project_dir" "$REPO_DIR"
  repo_build_dir="$REPO_DIR"
fi

(
  cd "$repo_build_dir"
  "$ZIG_BIN" build -Doptimize=ReleaseSafe --prefix "$INSTALL_DIR"
)

installed_exe="$INSTALL_DIR/bin/avocado"
if [[ ! -x "$installed_exe" ]]; then
  echo "error: installed executable not found at ${installed_exe}"
  exit 1
fi

cat >"$LAUNCHER_PATH" <<SH
#!/usr/bin/env bash
set -euo pipefail
exec "$installed_exe" "\$@"
SH
chmod +x "$LAUNCHER_PATH"

if command -v avocado >/dev/null 2>&1; then
  echo "ok: avocado is installed"
  echo "run: avocado"
  exit 0
fi

echo "installed, but 'avocado' is not on PATH in this shell"
echo "add ${BIN_DIR} to PATH, open a new terminal, then run: avocado"
