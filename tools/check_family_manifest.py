#!/usr/bin/env python3
"""Verify the Python family profiles against the machine-readable manifest."""

from __future__ import annotations

import json
from pathlib import Path

from victory_v.family import (
    ARCHITECTURES,
    DECISION_ENGINES,
    FAMILY_NAME,
    INSTRUCTION_WIDTH_BITS,
    SOURCE_ARCHITECTURE,
    SYSTEM_PROFILES,
    VRTU_PROFILES,
    validate_family,
)

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"family manifest error: {message}")


def main() -> None:
    validate_family()
    manifest = json.loads((ROOT / "isa" / "victory-v-family.json").read_text(encoding="utf-8"))
    if manifest["family"] != FAMILY_NAME:
        fail("family name differs")
    if manifest["source_architecture"] != SOURCE_ARCHITECTURE:
        fail("source architecture differs")
    if manifest["instruction_width_bits"] != INSTRUCTION_WIDTH_BITS:
        fail("instruction width differs")

    for name, profile in ARCHITECTURES.items():
        entry = manifest["architectures"].get(name)
        if entry is None:
            fail(f"missing architecture {name}")
        expected = {
            "status": profile.status,
            "xlen": profile.xlen,
            "address_bits": profile.address_bits,
            "translation": profile.translation,
            "inherits": profile.inherits,
            "hardware_target": profile.hardware_target,
        }
        for key, value in expected.items():
            if entry.get(key) != value:
                fail(f"{name}.{key}: {entry.get(key)!r} != {value!r}")
        if set(entry["required_rules"]) != set(profile.required_rules):
            fail(f"{name}: required rules differ")

    for name, profile in SYSTEM_PROFILES.items():
        entry = manifest["system_profiles"].get(name)
        if entry is None:
            fail(f"missing system profile {name}")
        for key, value in {
            "architecture": profile.architecture,
            "status": profile.status,
            "mmu": profile.mmu,
            "protection": profile.protection,
            "userspace_abi": profile.userspace_abi,
            "virtual_address_bits": profile.virtual_address_bits,
        }.items():
            if entry.get(key) != value:
                fail(f"{name}.{key}: {entry.get(key)!r} != {value!r}")

    for name, profile in VRTU_PROFILES.items():
        entry = manifest["vrtu_profiles"].get(name)
        if entry is None:
            fail(f"missing VRTU profile {name}")
        expected = {
            "entries": profile.entries,
            "address_bits": profile.address_bits,
            "software_refill": profile.software_refill,
            "page_walker": profile.page_walker,
            "locked_reset_map": profile.locked_reset_map,
        }
        if entry != expected:
            fail(f"{name}: VRTU profile differs")

    experiment = manifest.get("experiments", {}).get("EUCLID-experiment", {})
    if experiment.get("default_fpga_image") is not False or experiment.get("default_rtl_test") is not False:
        fail("Euclid experiment leaked into the default image or regression")
    if list(DECISION_ENGINES) != ["EUCLID-experiment"]:
        fail("unexpected decision-engine profile")

    print("family manifest matches Python profiles, VRTU profiles, and experiment isolation")


if __name__ == "__main__":
    main()
