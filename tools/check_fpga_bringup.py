#!/usr/bin/env python3
"""Check the Tang 138K three-core/VRTU bring-up files."""

from __future__ import annotations

import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FPGA = ROOT / "fpga" / "tang-138k"


def fail(message: str) -> None:
    raise SystemExit(f"FPGA bring-up error: {message}")


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
        if declarations.get(name) != definition["value"]:
            fail(f"VV64 base opcode moved: {name}")


def check_platform() -> None:
    manifest = json.loads((ROOT / "platform" / "tang-138k-1p1e1v32.json").read_text(encoding="utf-8"))
    cores = manifest.get("cores", [])
    if len(cores) != 3 or [core.get("id") for core in cores] != [0, 1, 2]:
        fail("platform must contain exactly VV32, P0, and E0")
    if "euclid" in manifest:
        fail("Euclid remains in the shipping platform manifest")
    p_core, e_core = cores[1], cores[2]
    if p_core.get("vrtu_entries") != 4 or e_core.get("vrtu_entries") != 2:
        fail("P0/E0 VRTU contract capacity must be 4/2")
    vrtu = manifest.get("vrtu", {})
    if vrtu.get("software_refill") is not False or vrtu.get("page_table_walker") is not False:
        fail("VRTU must not use software refill or a page walker")
    if vrtu.get("causes") != {"miss": 20, "permission": 21, "conflict": 22}:
        fail("VRTU causes differ from the A0 contract")
    if manifest.get("linux_target", {}).get("memory_protection") != "VRTU":
        fail("no-MMU Linux target is not protected by VRTU")


def check_vrtu_source() -> None:
    source = (ROOT / "rtl" / "memory" / "vv_vrtu.sv").read_text(encoding="utf-8")
    for marker in (
        "module vv_vrtu",
        "ENTRY_COUNT",
        "CAUSE_VRTU_MISS",
        "CAUSE_VRTU_PERMISSION",
        "CAUSE_VRTU_CONFLICT",
        "i_matches > 1",
        "d_matches > 1",
        "ig_generation_q",
        "dg_generation_q",
    ):
        if marker not in source:
            fail(f"VRTU RTL is missing {marker!r}")
    profile = (ROOT / "rtl" / "vv64_profiled_core.sv").read_text(encoding="utf-8")
    for marker in ("PROFILE_VRTU_ENTRIES", "u_vrtu", "core_imem_fault", "core_dmem_fault"):
        if marker not in profile:
            fail(f"VV64 profile wrapper is missing {marker!r}")



def check_vtry_bringup_rom() -> None:
    from gen_fpga_bringup import render

    path = ROOT / "rtl" / "boot" / "vv_bringup_rom.sv"
    checked_in = path.read_text(encoding="utf-8")
    if checked_in != render():
        fail("bring-up ROM differs from tools/gen_fpga_bringup.py")
    lower = checked_in.lower()
    if "v" + "enter" in lower:
        fail("retired prepared-entry spelling remains in the bring-up ROM")
    for marker in (
        "each core checks direct vtry commit",
        "vtry c14",
        "vprep c14",
        "vabt 0x7001",
        "vtry ready",
        "vtry fail",
    ):
        if marker not in lower:
            fail(f"bring-up ROM is missing {marker!r}")
    if lower.count("vtry c14") < 4:
        fail("not every ROM image exercises prepared VTRY")
    if lower.count("vtry 0x") < 8:
        fail("not every ROM image exercises direct VTRY commit and abort")


def check_projects() -> None:
    projects = sorted(FPGA.glob("*.gprj"))
    if len(projects) != 4:
        fail(f"expected four Gowin projects, found {len(projects)}")
    required = {
        "../../rtl/vv64_profiled_core.sv",
        "../../rtl/memory/vv_vrtu.sv",
        "../../rtl/soc/vv_cluster_bringup.sv",
    }
    forbidden = {
        "../../rtl/euclid/vv_euclid_a0.sv",
        "../../rtl/soc/vv_cluster_euclid_bringup.sv",
    }
    for project in projects:
        tree = ET.parse(project)
        device = tree.find("Device")
        if device is None or device.get("name") not in {"GW5AST-138B", "GW5AST-138C"}:
            fail(f"unexpected device in {project.name}")
        listed = {item.get("path") for item in tree.findall("./FileList/File") if item.get("path")}
        missing = required - listed
        if missing:
            fail(f"{project.name} is missing {sorted(missing)}")
        leaked = forbidden & listed
        if leaked:
            fail(f"{project.name} still ships Euclid: {sorted(leaked)}")
        for relative in listed:
            if not (project.parent / relative).resolve().is_file():
                fail(f"missing project source: {project.name}: {relative}")

    for top_name in ("mega_top.sv", "console_top.sv"):
        source = (FPGA / top_name).read_text(encoding="utf-8")
        if "vv_cluster_bringup" not in source:
            fail(f"{top_name} does not instantiate the three-core SoC")
        if "euclid" in source.lower():
            fail(f"{top_name} still contains an Euclid path")


def check_experiment_isolation() -> None:
    expected = (
        ROOT / "experiments" / "euclid" / "rtl" / "vv_euclid_a0.sv",
        ROOT / "experiments" / "euclid" / "tb" / "vv_euclid_a0_tb.sv",
        ROOT / "experiments" / "euclid" / "euclid.py",
    )
    if not all(path.is_file() for path in expected):
        fail("Euclid research history was not moved intact to experiments/euclid")
    forbidden_paths = (
        ROOT / "rtl" / "euclid" / "vv_euclid_a0.sv",
        ROOT / "rtl" / "soc" / "vv_cluster_euclid_bringup.sv",
        ROOT / "src" / "victory_v" / "euclid.py",
    )
    if any(path.exists() for path in forbidden_paths):
        fail("Euclid still exists in a shipping source path")


def main() -> None:
    check_opcode_continuity()
    check_platform()
    check_vrtu_source()
    check_vtry_bringup_rom()
    check_projects()
    check_experiment_isolation()
    print("Tang 138K three-core + VTRY + VRTU handoff files are internally consistent")


if __name__ == "__main__":
    main()
