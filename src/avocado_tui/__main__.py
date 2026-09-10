from __future__ import annotations

import argparse
from pathlib import Path

from .app import AvocadoApp


def _normalize_document_path(raw_path: str) -> Path:
    path = Path(raw_path).expanduser()
    if path.exists():
        return path.resolve(strict=False)
    if path.suffix.lower() == ".txt":
        return path.resolve(strict=False)
    if path.suffix:
        return path.with_suffix(".txt").resolve(strict=False)
    return path.with_name(path.name + ".txt").resolve(strict=False)


def main() -> None:
    parser = argparse.ArgumentParser(prog="avocado")
    parser.add_argument("path", nargs="?", default=None)
    args = parser.parse_args()

    if not args.path:
        AvocadoApp(None).run()
        return

    p = _normalize_document_path(args.path)
    if p.exists() and p.is_dir():
        parser.error(f"path is a directory: {p}")

    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.touch()

    AvocadoApp(str(p)).run()


if __name__ == "__main__":
    main()
