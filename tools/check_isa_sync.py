#!/usr/bin/env python3
"""Fail when JSON, Python, and RTL opcode declarations drift apart."""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from victory_v.isa import Cause, Csr, Opcode  # noqa: E402


OPCODE_RE = re.compile(r"localparam\s+logic\s+\[5:0\]\s+OP_([A-Z0-9_]+)\s*=\s*6'h([0-9a-fA-F]+)\s*;")
CSR_RE = re.compile(r"localparam\s+logic\s+\[15:0\]\s+CSR_([A-Z0-9_]+)\s*=\s*16'h([0-9a-fA-F]+)\s*;")
CAUSE_RE = re.compile(r"localparam\s+logic\s+\[15:0\]\s+CAUSE_([A-Z0-9_]+)\s*=\s*16'd([0-9]+)\s*;")


def fail(message: str) -> None:
    print(f"ISA sync error: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    manifest = json.loads((ROOT / "isa" / "vv32-a0.json").read_text(encoding="utf-8"))
    rtl = (ROOT / "rtl" / "vv32_pkg.sv").read_text(encoding="utf-8")

    json_opcodes = {name: int(entry["value"]) for name, entry in manifest["opcodes"].items()}
    python_opcodes = {name: int(value) for name, value in Opcode.__members__.items()}
    rtl_opcodes = {name: int(value, 16) for name, value in OPCODE_RE.findall(rtl)}
    if json_opcodes != python_opcodes:
        fail(f"JSON/Python opcode mismatch\nJSON={json_opcodes}\nPython={python_opcodes}")
    if rtl_opcodes != python_opcodes:
        fail(f"RTL/Python opcode mismatch\nRTL={rtl_opcodes}\nPython={python_opcodes}")

    json_csrs = {name: int(value) for name, value in manifest["csrs"].items()}
    python_csrs = {name: int(value) for name, value in Csr.__members__.items()}
    rtl_csrs = {name: int(value, 16) for name, value in CSR_RE.findall(rtl)}
    if json_csrs != python_csrs or rtl_csrs != python_csrs:
        fail("CSR declarations are not synchronized")

    json_causes = {name: int(value) for name, value in manifest["causes"].items()}
    python_causes = {name: int(value) for name, value in Cause.__members__.items()}
    rtl_causes = {name: int(value, 10) for name, value in CAUSE_RE.findall(rtl)}
    if json_causes != python_causes or rtl_causes != python_causes:
        fail("cause declarations are not synchronized")

    print(f"ISA declarations synchronized: {len(python_opcodes)} opcodes, {len(python_csrs)} CSRs, {len(python_causes)} causes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
