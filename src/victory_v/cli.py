"""Command-line tools for the VICTORY-V repository."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from .assembler import assemble_file, words_from_bytes
from .disassembler import disassemble
from .errors import VictoryError
from .family import ARCHITECTURES, DECISION_ENGINES, SYSTEM_PROFILES, VRTU_PROFILES
from .machine import Machine, MachineConfig


def _load_words(path: Path) -> tuple[int, ...]:
    if path.suffix.lower() in {".vs", ".s", ".asm"}:
        return assemble_file(path).words
    return words_from_bytes(path.read_bytes())


def _cmd_asm(args: argparse.Namespace) -> int:
    program = assemble_file(args.source)
    program.write(args.output)
    if args.listing:
        lines = disassemble(program.words)
        listing = "\n".join(
            f"{index * 4:08x}: {word:08x}  {text}"
            for index, (word, text) in enumerate(zip(program.words, lines, strict=True))
        )
        Path(args.listing).write_text(listing + "\n", encoding="utf-8")
    print(f"assembled {len(program.words)} instruction word(s) -> {args.output}")
    return 0


def _cmd_disasm(args: argparse.Namespace) -> int:
    path = Path(args.program)
    words = _load_words(path)
    for index, (word, text) in enumerate(zip(words, disassemble(words, base_pc=args.base), strict=True)):
        print(f"{args.base + index * 4:08x}: {word:08x}  {text}")
    return 0


def _cmd_run(args: argparse.Namespace) -> int:
    words = _load_words(Path(args.program))
    machine = Machine(MachineConfig(memory_size=args.memory, region_store_depth=args.store_depth))
    machine.load_program(words)
    result = machine.run(max_steps=args.max_steps, trace=args.trace)

    if args.trace:
        for event in machine.trace:
            print(f"{event.cycle:08d}  pc={event.pc:08x}  {event.word:08x}  {event.note}")

    print(
        "status="
        + ("FAULT" if result.faulted else "HALT" if result.halted else "WAIT" if result.waiting else "LIMIT")
        + f" pc=0x{result.pc:08x} cause={result.cause} victory_error={result.victory_error} steps={result.steps}"
    )
    if args.registers:
        for row in range(0, 32, 4):
            print("  ".join(f"r{index:02d}=0x{machine.registers[index]:08x}" for index in range(row, row + 4)))

    return 1 if result.faulted else 0


def _cmd_profiles(_args: argparse.Namespace) -> int:
    rows: list[tuple[str, str, str, str, str, str]] = []
    for profile in ARCHITECTURES.values():
        rows.append(("CPU", profile.name, str(profile.xlen), profile.translation, profile.status, profile.hardware_target))
    for profile in SYSTEM_PROFILES.values():
        architecture = ARCHITECTURES[profile.architecture]
        rows.append(
            (
                "SYSTEM",
                profile.name,
                str(architecture.xlen),
                "required" if profile.mmu else "none",
                profile.status,
                architecture.hardware_target,
            )
        )
    for profile in VRTU_PROFILES.values():
        rows.append(("VRTU", profile.name, "-", f"{profile.entries} exact ranges", "rtl-alpha", "Tang 138K"))
    for profile in DECISION_ENGINES.values():
        rows.append(("EXPERIMENT", profile.name, "-", "-", profile.status, profile.hardware_target))

    headings = ("KIND", "PROFILE", "XLEN", "TRANSLATION", "STATUS", "TARGET")
    widths = [max(len(headings[index]), *(len(row[index]) for row in rows)) for index in range(len(headings))]
    print("  ".join(headings[index].ljust(widths[index]) for index in range(len(headings))))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(row[index].ljust(widths[index]) for index in range(len(row))))
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="vv", description="VICTORY-V command-line tools")
    subparsers = parser.add_subparsers(dest="command", required=True)

    asm = subparsers.add_parser("asm", help="assemble a VV32-A0 source file")
    asm.add_argument("source", type=Path)
    asm.add_argument("-o", "--output", type=Path, required=True)
    asm.add_argument("--listing", type=Path)
    asm.set_defaults(func=_cmd_asm)

    disasm = subparsers.add_parser("disasm", help="disassemble VV32-A0 source or binary")
    disasm.add_argument("program")
    disasm.add_argument("--base", type=lambda value: int(value, 0), default=0)
    disasm.set_defaults(func=_cmd_disasm)

    run = subparsers.add_parser("run", help="run VV32-A0 source or binary in the reference model")
    run.add_argument("program")
    run.add_argument("--memory", type=lambda value: int(value, 0), default=64 * 1024)
    run.add_argument("--store-depth", type=int, default=8)
    run.add_argument("--max-steps", type=int, default=100_000)
    run.add_argument("--trace", action="store_true")
    run.add_argument("--registers", action="store_true")
    run.set_defaults(func=_cmd_run)

    profiles = subparsers.add_parser("profiles", help="show CPU, system, and decision-engine profiles")
    profiles.set_defaults(func=_cmd_profiles)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except (VictoryError, ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
