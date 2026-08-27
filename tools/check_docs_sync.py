#!/usr/bin/env python3
"""Catch stale architecture claims and accidental README layout drift."""

from __future__ import annotations

from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "README.md": (
        "Declare what the work may spend",
        "## Victory Contracts",
        "VTRY cToken, fail",
        "complete write-set",
        "VV32-A0 VTRY ready",
        "The old Euclid nearest-neighbour block is not in the default FPGA image.",
        "experiments/euclid/",
        "VICTORY-V-hero-v1.png",
        "style=for-the-badge",
    ),
    "docs/ARCHITECTURE.md": (
        "vprep  cToken, cArena, rSpec",
        "vtry   cToken, failure_target",
        "`ST_PREFLIGHT` probes every buffered entry",
        "checked-in ROM runs direct `VTRY` commit",
    ),
    "docs/ISA.md": (
        "`0x3c` | `VPREP",
        "`0x3d` | `VTRY cToken, fail`",
        "`VTRYC`",
        "`0x000b` | `VCONTRACT`",
        "| 31 | invalid VRTU configuration |",
    ),
    "docs/VV64.md": (
        "32-bit-generation Capability Directory",
        "`VTRY cToken, fail`",
        "`ST_PREFLIGHT`",
        "boot ROM exercises direct `VTRY`",
    ),
    "docs/VRTU.md": (
        "no software refill",
        "generation[31:0]",
        "`VRTU_CONFIGURATION`",
    ),
    "docs/A0_FPGA_HANDOFF.md": (
        "`VPREP` followed by `VTRY cToken, fail`",
        "probes every entry before any write is issued",
        "generated ROM is also run through the executable model",
    ),
    "docs/THREAT_MODEL.md": (
        "one-shot contract-token admission",
        "complete write set is preflighted",
        "archived Euclid code is outside the shipping image",
    ),
    "docs/ROADMAP.md": (
        "prepared `VTRY` / `VCANCEL`",
        "direct/prepared `VTRY` and rollback self-tests",
        "merged write-set buffering and all-entry commit preflight",
    ),
    "docs/FPGA_138K_BRINGUP.md": (
        "VV64-A0/P0 + VRTU-P0",
        "VV32-A0 VTRY ready",
        "make rtl-test-vrtu",
    ),
    "docs/FPGA_HANDOFF.md": (
        "direct/prepared `VTRY`",
        "VV32-A0 VTRY ready",
        "Euclid is not in the default image",
    ),
    "docs/LINUX_PORT.md": ("CONFIG_MMU=n", "VRTU flat range protection"),
    "docs/HETEROGENEOUS_CLUSTER.md": ("VRTU ranges", "VTRY ready", "4", "2"),
    "docs/USAGE_JA.md": ("VTRY cToken, fail", "VTRY ready"),
    "CHANGELOG.md": (
        "0.7.0-alpha.0",
        "Removed the separate prepared-entry mnemonic",
        "Tang 138K first-light ROM checks",
    ),
}



def fail(message: str) -> None:
    raise SystemExit(f"documentation sync error: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        fail(f"missing {relative}")
    return path.read_text(encoding="utf-8")


def main() -> None:
    for relative, markers in REQUIRED.items():
        text = read(relative)
        for marker in markers:
            if marker not in text:
                fail(f"{relative} is missing {marker!r}")

    readme = read("README.md")
    for anchor in (
        '<div align="center">',
        "### Verified, Isolated, Capability-safe",
        "VICTORY-V-hero-v1.png",
        "style=for-the-badge",
        "**[Quick start]",
        "## The name",
    ):
        if anchor not in readme:
            fail(f"README layout anchor disappeared: {anchor}")

    def section(heading: str, next_heading: str) -> str:
        try:
            begin = readme.index(heading)
            finish = readme.index(next_heading, begin + len(heading))
        except ValueError as exc:
            fail(f"README section boundary is missing: {heading}")
            raise AssertionError from exc
        return readme[begin:finish]

    for heading, next_heading in (
        ("## The family", "## Rules carried by both widths"),
        ("## Tang 138K cluster", "## What is in the repository"),
        ("## Road to Linux and DOOM", "## Repository map"),
    ):
        if "euclid" in section(heading, next_heading).lower():
            fail(f"retired Euclid block returned to README section {heading!r}")

    forbidden_readme = (
        "Euclid-A0",
        "Euclid Plane",
        "vv_cluster_euclid_bringup",
        "led[7:6]",
        "attached decision engine",
        "Euclid RTL slice",
    )
    for phrase in forbidden_readme:
        if phrase.lower() in readme.lower():
            fail(f"README contains retired shipping claim {phrase!r}")

    for line in readme.splitlines():
        lower = line.lower()
        if "euclid" not in lower:
            continue
        if not any(
            marker in lower
            for marker in (
                "not in the default fpga image",
                "without carrying the euclid datapath",
                "archived euclid experiment",
                "archived early-decision research",
                "make experiment-euclid",
                "retired euclid work",
            )
        ):
            fail(f"README has an unqualified Euclid claim: {line.strip()!r}")

    architecture = read("docs/ARCHITECTURE.md")
    for stale in (
        "Ordinary registers and non-secret capabilities are not rolled back",
        "External interrupts are deferred while a region",
        "scrubs secret registers, and jumps to the failure target",
        "The inherited `VTRY` behavior remains unchanged",
        "The current RTL still publishes a multi-entry buffer one beat at a time",
        "A0 replay boundary",
    ):
        if stale in architecture:
            fail(f"ARCHITECTURE.md still contains superseded text: {stale!r}")

    isa_python = read("src/victory_v/isa.py")
    vv32_pkg = read("rtl/vv32_pkg.sv")
    vv64_pkg = read("rtl/vv64_pkg.sv")
    vv64_core = read("rtl/vv64_core.sv")
    for source, markers in (
        (isa_python, ("VPREP = 0x3C", "VTRYC = 0x3D", "VCONTRACT = 0x000B", "VRTU_CONFIGURATION = 31")),
        (vv32_pkg, ("OP_VPREP", "OP_VTRYC", "CAUSE_COMMIT_PROTOCOL", "ST_PREFLIGHT")),
        (vv64_pkg, ("OP_VPREP", "OP_VTRYC", "CAUSE_COMMIT_PROTOCOL", "ST_PREFLIGHT")),
        (vv64_core, ("CAP_GENERATION_BITS = 32", "dmem_probe_o", "ST_PREFLIGHT")),
    ):
        for marker in markers:
            if marker not in source:
                fail(f"implemented contract marker disappeared: {marker!r}")

    retired_entry = ("v" + "enter").lower()
    suffixes_for_entry = {".md", ".py", ".sv", ".json"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in suffixes_for_entry:
            continue
        if retired_entry in path.read_text(encoding="utf-8").lower():
            fail(f"retired prepared-entry spelling remains in {path.relative_to(ROOT)}")

    rom = read("rtl/boot/vv_bringup_rom.sv").lower()
    for marker in ("vtry c14", "vabt 0x7001", "vtry ready", "vtry fail"):
        if marker not in rom:
            fail(f"bring-up ROM is missing {marker!r}")
    if rom.count("vtry c14") < 4:
        fail("not every bring-up image contains prepared VTRY")

    forbidden_paths = (
        ROOT / "src" / "victory_v" / "euclid.py",
        ROOT / "rtl" / "euclid" / "vv_euclid_a0.sv",
        ROOT / "rtl" / "soc" / "vv_cluster_euclid_bringup.sv",
        ROOT / "rtl" / "tb" / "vv_euclid_a0_tb.sv",
    )
    if any(path.exists() for path in forbidden_paths):
        fail("Euclid still exists in a shipping source path")

    for path in list((ROOT / "fpga" / "tang-138k").glob("*.gprj")) + [
        ROOT / "fpga" / "tang-138k" / "console_top.sv",
        ROOT / "fpga" / "tang-138k" / "mega_top.sv",
    ]:
        text = path.read_text(encoding="utf-8").lower()
        if "euclid" in text:
            fail(f"Euclid remains in the default FPGA image: {path.relative_to(ROOT)}")
        if path.suffix == ".gprj" and "vv_vrtu.sv" not in text:
            fail(f"VRTU missing from {path.relative_to(ROOT)}")

    platform = read("platform/tang-138k-1p1e1v32.json")
    if '"euclid"' in platform.lower() or '"memory_protection": "VRTU"' not in platform:
        fail("platform manifest is stale")

    retired = ("DE" + "FEAT-V", "DE" + "FEAT_V", "敗" + "者-V", "敗" + "者ーV")
    suffixes = {".md", ".py", ".sv", ".json", ".toml", ".yml", ".yaml"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in suffixes:
            continue
        text = path.read_text(encoding="utf-8")
        for term in retired:
            if term in text:
                fail(f"retired name {term!r} remains in {path.relative_to(ROOT)}")

    project_version = tomllib.loads(read("pyproject.toml"))["project"]["version"]
    init_text = read("src/victory_v/__init__.py")
    match = re.search(r'__version__\s*=\s*"([^"]+)"', init_text)
    if match is None or match.group(1) != project_version:
        fail("pyproject.toml and victory_v.__version__ differ")
    if project_version != "0.7.0a0":
        fail(f"unexpected project version: {project_version}")

    print(f"documentation state synchronized for {len(REQUIRED)} tracked files")


if __name__ == "__main__":
    main()
