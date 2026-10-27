#!/usr/bin/env python3
"""Sync the canonical Starship config to its optional Wallust template.

Both use ANSI palette indices, so no palette substitution or installation into
the user's home is needed. rice-switch.sh links the canonical file directly.
"""

from pathlib import Path


def main():
    repo = Path(__file__).resolve().parents[1]
    source = repo / "starship.toml"
    target = repo / "wallust/templates/colors-starship.toml"
    target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
    print("wrote", target)


if __name__ == "__main__":
    main()
