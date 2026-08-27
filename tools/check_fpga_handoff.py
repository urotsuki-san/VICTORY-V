#!/usr/bin/env python3
"""Static handoff checks for all Tang 138K project variants."""

from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FPGA = ROOT / "fpga" / "tang-138k"
PROJECTS = (
    "victory_v_console_138k_b.gprj",
    "victory_v_console_138k_c.gprj",
    "victory_v_mega_138k_b.gprj",
    "victory_v_mega_138k_c.gprj",
)
REQUIRED = {
    "vv32_pkg.sv", "vv32_core.sv", "vv64_pkg.sv", "vv64_core.sv",
    "vv64_profiled_core.sv", "vv_vrtu.sv", "vv_reset_sync.sv",
    "vv_sram.sv", "vv_uart_tx.sv", "vv_bringup_rom.sv",
    "vv_cluster_bringup.sv",
}
FORBIDDEN = {"vv_euclid_a0.sv", "vv_cluster_euclid_bringup.sv"}


def refs(text: str) -> set[str]:
    return set(re.findall(r'path="([^"]+\.(?:sv|v|cst|sdc))"', text, re.I))


def main() -> None:
    source_sets: list[set[str]] = []
    for name in PROJECTS:
        path = FPGA / name
        if not path.is_file():
            raise SystemExit(f"missing FPGA project: {path.relative_to(ROOT)}")
        found = refs(path.read_text(encoding="utf-8"))
        basenames = {Path(item.replace("\\", "/")).name for item in found}
        missing = sorted(REQUIRED - basenames)
        forbidden = sorted(FORBIDDEN & basenames)
        if missing:
            raise SystemExit(f"{name}: missing sources: {', '.join(missing)}")
        if forbidden:
            raise SystemExit(f"{name}: archived experiment is still shipped: {', '.join(forbidden)}")
        unresolved = [
            item for item in found
            if not (path.parent / item.replace("\\", "/")).resolve().is_file()
        ]
        if unresolved:
            raise SystemExit(f"{name}: unresolved paths: {', '.join(sorted(unresolved))}")
        source_sets.append(basenames)
        print(f"FPGA handoff OK: {name} ({len(found)} files)")

    if source_sets[0] != source_sets[1]:
        raise SystemExit("Console B/C project source sets differ")
    if source_sets[2] != source_sets[3]:
        raise SystemExit("Mega B/C project source sets differ")
    for sdc in (FPGA / "console.sdc", FPGA / "mega.sdc"):
        text = sdc.read_text(encoding="utf-8")
        if "create_clock" not in text or "20" not in text:
            raise SystemExit(f"{sdc.name}: 50 MHz / 20 ns clock constraint missing")
    for top in (FPGA / "console_top.sv", FPGA / "mega_top.sv"):
        text = top.read_text(encoding="utf-8")
        if "vv_cluster_bringup" not in text or "euclid" in text.lower():
            raise SystemExit(f"{top.name}: default top is not the three-core VRTU image")

    rom = (ROOT / "rtl" / "boot" / "vv_bringup_rom.sv").read_text(encoding="utf-8").lower()
    for marker in ("vtry c14", "vabt 0x7001", "vtry ready"):
        if marker not in rom:
            raise SystemExit(f"bring-up ROM does not prove {marker!r}")
    if "v" + "enter" in rom:
        raise SystemExit("bring-up ROM still uses the retired prepared-entry spelling")

    print("Tang 138K handoff contains three CPUs, VTRY self-tests, and VRTU, with Euclid excluded")


if __name__ == "__main__":
    main()
