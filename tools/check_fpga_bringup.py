#!/usr/bin/env python3
"""Check the Tang 138K cluster files without running the FPGA tools."""

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
    for marker in ("VV32-A0 ready", "VV64-P0 ready", "VV64-E0 ready"):
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


def check_platform_manifest() -> None:
    path = ROOT / "platform" / "tang-138k-1p1e1v32.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "victory-v.platform.v1":
        fail("unexpected platform manifest schema")
    cores = manifest.get("cores")
    if not isinstance(cores, list) or len(cores) != 3:
        fail("Tang 138K platform must contain exactly three cores")
    by_id = {core["id"]: core for core in cores}
    if sorted(by_id) != [0, 1, 2]:
        fail("core IDs must be 0, 1, and 2")
    expected = {
        0: ("VV32-A0", "control", "monitor-io"),
        1: ("VV64-A0", "P0", "linux-primary"),
        2: ("VV64-A0", "E0", "linux-secondary"),
    }
    for core_id, values in expected.items():
        core = by_id[core_id]
        actual = (core["architecture"], core["implementation"], core["role"])
        if actual != values:
            fail(f"core {core_id} does not match the 1P1E+VV32 contract: {actual!r}")
    if by_id[1]["capability_directory_entries"] <= by_id[2]["capability_directory_entries"]:
        fail("P0 must have a larger Capability Directory than E0")
    if by_id[1]["store_buffer_entries"] <= by_id[2]["store_buffer_entries"]:
        fail("P0 must have a deeper store buffer than E0")
    if manifest.get("boot_order") != [0, 1, 2]:
        fail("boot order must be VV32, P0, E0")
    linux = manifest.get("linux_target", {})
    if linux.get("profile") != "VV64-L0-flat" or linux.get("mmu") is not False:
        fail("the first Linux target must remain VV64-L0-flat with MMU disabled")
    mmio = manifest.get("mmio", {})
    addresses = list(mmio.values())
    if len(addresses) != len(set(addresses)):
        fail("MMIO addresses are not unique")
    if min(addresses) != manifest["memory"]["mmio_base"]:
        fail("MMIO map does not start at mmio_base")
    if max(addresses) >= manifest["memory"]["capability_root_end"]:
        fail("MMIO map escapes the initial root capability")


def check_profile_wrapper() -> None:
    wrapper = (ROOT / "rtl" / "vv64_profiled_core.sv").read_text(encoding="utf-8")
    required = (
        "PERFORMANCE_PROFILE ? 8 : 2",
        "PERFORMANCE_PROFILE ? 32 : 8",
        ".STORE_BUFFER_DEPTH (PROFILE_STORE_BUFFER_DEPTH)",
        ".CAP_DIRECTORY_ENTRIES (PROFILE_CAP_DIRECTORY_ENTRIES)",
    )
    for text in required:
        if text not in wrapper:
            fail(f"VV64 profile wrapper is missing {text!r}")


def check_cluster_source() -> None:
    source = (ROOT / "rtl" / "soc" / "vv_cluster_bringup.sv").read_text(encoding="utf-8")
    required = (
        "module vv_cluster_bringup",
        "u_vv32",
        "u_vv64_p",
        "u_vv64_e",
        ".PERFORMANCE_PROFILE (1'b1)",
        ".PERFORMANCE_PROFILE (1'b0)",
        "MAILBOX_P",
        "MAILBOX_E",
        "TIMEBASE_REG",
        "TIMER_P_REG",
        "TIMER_E_REG",
        "IPI_SET_REG",
        "IPI_CLEAR_REG",
    )
    for text in required:
        if text not in source:
            fail(f"cluster source is missing {text!r}")


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
        listed = set()
        for item in tree.findall("./FileList/File"):
            relative = item.get("path")
            if not relative:
                fail(f"empty file entry in {project}")
            listed.add(relative)
            source = (project.parent / relative).resolve()
            if not source.is_file():
                fail(f"missing project source: {project.name}: {relative}")
        for required in (
            "../../rtl/vv64_profiled_core.sv",
            "../../rtl/soc/vv_cluster_bringup.sv",
        ):
            if required not in listed:
                fail(f"{project.name} does not include {required}")


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
    check_platform_manifest()
    check_profile_wrapper()
    check_cluster_source()
    check_projects()
    check_board_constraints()
    print("Tang 138K 1P1E+VV32 files are internally consistent")


if __name__ == "__main__":
    main()
