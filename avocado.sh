#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"

if [[ -z "${ZIG_BIN}" ]]; then
  echo "error: zig not found (need Zig 0.16+)" >&2
  exit 1
fi

cd "$REPO_ROOT"
exec "$ZIG_BIN" build run -- "$@"
