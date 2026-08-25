#!/usr/bin/env python3
"""Assemble a VICTORY-V source file into a word-oriented readmemh file."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from victory_v.assembler import assemble_file  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    program = assemble_file(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(f"{word:08x}" for word in program.words) + "\n", encoding="ascii")
    print(f"wrote {len(program.words)} words to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
