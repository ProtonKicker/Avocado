from __future__ import annotations

import argparse
from pathlib import Path

from .app import AvocadoApp


def main() -> None:
    parser = argparse.ArgumentParser(prog="avocado")
    parser.add_argument("path", nargs="?", default=None)
    args = parser.parse_args()

    if not args.path:
        AvocadoApp(None).run()
        return

    p = Path(args.path).expanduser().resolve(strict=False)
    if p.exists() and p.is_dir():
        parser.error(f"path is a directory: {p}")

    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.touch()

    AvocadoApp(str(p)).run()


if __name__ == "__main__":
    main()
