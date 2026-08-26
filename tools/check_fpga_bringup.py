#!/usr/bin/env python3
"""Check the files that make up the Tang 138K bring-up image."""

from __future__ import annotations

import importlib.util
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(message)


def load_generator():
    path = ROOT / "tools" / "gen_fpga_bringup.py"
    spec = importlib.util.spec_from_file_location("gen_fpga_bringup", path)
    if spec is None or spec.loader is None:
        fail(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_generated_rom() -> None:
    generator = load_generator()
    expected = generator.render()
    path = ROOT / "rtl" / "boot" / "vv_bringup_rom.sv"
    actual = path.read_text(encoding="utf-8")
    if actual != expected:
        fail("rtl/boot/vv_bringup_rom.sv is stale; run tools/gen_fpga_bringup.py")
    for marker in ("VV32-A0 ready", "VV64-A0 ready"):
        if marker not in actual:
            fail(f"bring-up ROM does not contain {marker!r}")


def check_opcode_continuity() -> None:
    manifest = json.loads((ROOT / "isa" / "vv32-a0.json").read_text(encoding="utf-8"))
    package = (ROOT / "rtl" / "vv64_pkg.sv").read_text(encoding="utf-8")
    declarations = {
        name: int(value, 16)
        for name, value in re.findall(
            r"localparam\s+logic\s+\[5:0\]\s+OP_([A-Z0-9_]+)\s*=\s*6'h([0-9a-fA-F]+)",
            package,
        )
    }
    for name, definition in manifest["opcodes"].items():
        actual = declarations.get(name)
        if actual != definition["value"]:
            fail(f"VV64 base opcode moved: {name} expected {definition['value']:#x}, got {actual!r}")


def check_projects() -> None:
    project_dir = ROOT / "fpga" / "tang-138k"
    projects = sorted(project_dir.glob("*.gprj"))
    if len(projects) != 4:
        fail(f"expected four Gowin projects, found {len(projects)}")
    for project in projects:
        tree = ET.parse(project)
        device = tree.find("Device")
        if device is None or device.get("name") not in {"GW5AST-138B", "GW5AST-138C"}:
            fail(f"unexpected device in {project}")
        for item in tree.findall("./FileList/File"):
            relative = item.get("path")
            if not relative:
                fail(f"empty file entry in {project}")
            source = (project.parent / relative).resolve()
            if not source.is_file():
                fail(f"missing project source: {project.name}: {relative}")


def check_board_constraints() -> None:
    project_dir = ROOT / "fpga" / "tang-138k"
    mega = (project_dir / "mega.cst").read_text(encoding="utf-8")
    console = (project_dir / "console.cst").read_text(encoding="utf-8")
    required_mega = {'"clk" V22', '"uart_tx" U15', '"uart_rx" V14', '"led_V13" V13'}
    required_console = {'"clk50" V22', '"UART_TXD" U15', '"UART_RXD" V14'}
    for entry in required_mega:
        if entry not in mega:
            fail(f"Mega constraint missing {entry}")
    for entry in required_console:
        if entry not in console:
            fail(f"Console constraint missing {entry}")


def main() -> None:
    check_generated_rom()
    check_opcode_continuity()
    check_projects()
    check_board_constraints()
    print("FPGA bring-up files are internally consistent")


if __name__ == "__main__":
    main()
