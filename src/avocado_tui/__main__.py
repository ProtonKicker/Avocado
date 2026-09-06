from __future__ import annotations

import argparse

from .app import AvocadoApp


def main() -> None:
    parser = argparse.ArgumentParser(prog="avocado")
    parser.add_argument("path", nargs="?", default=None)
    args = parser.parse_args()

    AvocadoApp(args.path).run()


if __name__ == "__main__":
    main()

